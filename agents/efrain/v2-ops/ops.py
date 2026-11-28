#!/usr/bin/python3 -I
"""Montara V2: fixed operations only. Not an installer or a deployment API."""
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import stat
import subprocess
import sys
import syslog
import tarfile
import tempfile
import time
import tomllib

HTTP="montara-pilot-http.service"
INGRESS="montara-pilot-ingress.service"
WORKER="montara-pilot-worker.service"
ACL="montara-pilot-acl.service"
ENROL="montara-pilot-enrol.service"
PINS={HTTP:"d39310dd76febab0dfa371ee536c56832c9d53c1",
      INGRESS:"ebad4fc19cc26a7243541b395c2366d0b46e1278",
      WORKER:"6d9df7806b9567aa5fef4467f6984ef69f26af30",
      ACL:"1675a3a57a303ef78c514714e3081c628150c20d"}
DROP="/etc/systemd/system/montara-pilot-http.service.d/acl.conf"
DROP_BYTES=b"[Unit]\nRequires=montara-pilot-acl.service\nAfter=montara-pilot-acl.service\nBindsTo=montara-pilot-acl.service\nConflicts=montara-pilot-enrol.service\n"
BASE=Path("/opt/montara-pilot")
SLOT=BASE/"releases/c7e11118d2d1"
STATE=Path("/var/lib/montara-pilot")
BACKUPS=Path("/var/lib/montara-v2-backups")
LOCK=Path("/var/lib/montara-worker-delegation/worker.lock")
CFG=Path("/etc/montara-pilot/core.toml")
ACTIONS=("status","start","stop","restart","backup")
PROPS=("LoadState","ActiveState","SubState","MainPID","Result","ControlGroup",
       "FragmentPath","DropInPaths","NeedDaemonReload","UnitFileState","Job")
ENV={"PATH":"/usr/sbin:/usr/bin:/sbin:/bin","LC_ALL":"C","HOME":"/root"}
GIB=1024**3
MAX_BYTES=4*GIB
MAX_FILES=20000
MAX_BACKUPS=2

class Refused(Exception):
    pass

def require(ok, reason):
    if not ok:
        raise Refused(reason)

def command(*args, timeout=30):
    # No shell, inherited environment, user-supplied commands or paths.
    try:
        r=subprocess.run(args,env=ENV,cwd="/",stdin=subprocess.DEVNULL,
                         stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,
                         timeout=timeout,check=False)
    except (OSError,subprocess.TimeoutExpired):
        raise Refused("COMMAND_UNAVAILABLE_OR_TIMEOUT") from None
    require(r.returncode==0,"COMMAND_FAILED")
    return r.stdout

def sha(path, algo="sha256"):
    with path.open("rb") as f:
        return hashlib.file_digest(f,algo).hexdigest()

def root_file(p):
    s=p.lstat()
    require(stat.S_ISREG(s.st_mode) and s.st_uid==0 and not s.st_mode&0o022,
            "UNTRUSTED_CONTROL_FILE")
    require(p.resolve()==p,"NONCANONICAL_CONTROL_FILE")
    return p

def git_blob(p):
    raw=root_file(p).read_bytes()
    return hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\0"+raw).hexdigest()

def root_dir(p, private=False):
    s=p.lstat()
    require(stat.S_ISDIR(s.st_mode) and s.st_uid==0 and not s.st_mode&0o022 and p.resolve()==p,
            "UNTRUSTED_CONTROL_DIR")
    if private: require(stat.S_IMODE(s.st_mode)==0o700,"PRIVATE_DIR_MODE")

def props(raw):
    d={}
    for line in raw.decode().splitlines():
        k,sep,v=line.partition("=")
        require(sep and k in PROPS and k not in d,"INVALID_UNIT_STATUS")
        d[k]=v
    require(set(d)==set(PROPS),"INCOMPLETE_UNIT_STATUS")
    return d

def quiet(d):
    return d["ActiveState"] in ("inactive","failed") and d["MainPID"]=="0" and d["Job"] in ("","0")

def safe_worker(d):
    return quiet(d) and d["ActiveState"]=="inactive" and d["Result"]=="success"

def final_cycle(rc, d):
    """Classification for next worker launcher; never asserts publication."""
    if (rc!=0 or d.get("ActiveState")!="inactive" or d.get("SubState")!="dead"
        or d.get("MainPID")!="0" or d.get("Result")!="success"):
        return "REVIEW_REQUIRED"
    pair=(d.get("ExecMainCode"),d.get("ExecMainStatus"))
    return {("1","0"):"EXIT_ZERO_RETAINED",("0","0"):"EXIT_METADATA_UNAVAILABLE"}.get(pair,"REVIEW_REQUIRED")

def validate_acl(data,uid):
    require(isinstance(data,list) and all(set(x) in ({"metainfo"},{"table"},{"chain"},{"rule"}) for x in data),"ACL_DRIFT")
    ts=[x["table"] for x in data if "table" in x]
    cs=[x["chain"] for x in data if "chain" in x]
    rs=[x["rule"] for x in data if "rule" in x]
    require(len(ts)==len(cs)==1 and len(rs)==2,"ACL_DRIFT")
    require((ts[0]["family"],ts[0]["name"])==("inet","montara_pilot_v2"),"ACL_DRIFT")
    c=cs[0]
    require(tuple(c[k] for k in ("family","table","name","type","hook","prio","policy"))==
            ("inet","montara_pilot_v2","local_output","filter","output",-5,"accept"),"ACL_DRIFT")
    for r,port in zip(rs,(8080,20246)):
        require(tuple(r[k] for k in ("family","table","chain"))==("inet","montara_pilot_v2","local_output"),"ACL_DRIFT")
        expr=r["expr"]
        require(len(expr) in (4,5) and set(expr[-1])=={"reject"},"ACL_DRIFT")
        m=[x["match"] for x in expr[:-1]]
        if len(m)==4:
            p=m.pop(1)
            require(p["op"]=="==" and p["left"]=={"meta":{"key":"l4proto"}} and p["right"] in ("tcp",6),"ACL_DRIFT")
        require(m[0]=={"op":"==","left":{"meta":{"key":"oifname"}},"right":"lo"},"ACL_DRIFT")
        require(m[1]=={"op":"==","left":{"payload":{"protocol":"tcp","field":"dport"}},"right":port},"ACL_DRIFT")
        require(m[2]["op"]=="!=" and m[2]["left"]=={"meta":{"key":"skuid"}},"ACL_DRIFT")
        require(set(m[2]["right"]["set"])=={0,uid} if port==8080 else m[2]["right"]==0,"ACL_DRIFT")

@contextlib.contextmanager
def exclusive():
    # Same inode as already authorized worker launcher; don't create/delete it.
    root_dir(LOCK.parent)
    fd=os.open(LOCK,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        s=os.fstat(fd)
        require(stat.S_ISREG(s.st_mode) and s.st_uid==0 and s.st_nlink==1 and stat.S_IMODE(s.st_mode)==0o444,"LOCK_DRIFT")
        try: fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError: raise Refused("WORKER_OR_MAINTENANCE_BUSY") from None
        yield
    finally: os.close(fd)

def inventory(state, uid):
    # No symlinks, special files, external mounts or hardlinks outside archive.
    device=state.stat().st_dev
    entries={}
    links={}
    total=0
    for name in ("db","originals","attempts","artifacts"):
        root=state/name
        require(root.resolve()==root,"NONCANONICAL_DATA_ROOT")
        stack=[root]
        while stack:
            p=stack.pop()
            s=p.lstat()
            require(s.st_uid==uid and s.st_dev==device and not s.st_mode&0o077,"UNEXPECTED_DATA_OWNER_MODE_OR_MOUNT")
            rel=p.relative_to(state).as_posix()
            require(len(entries)<MAX_FILES,"BACKUP_FILE_LIMIT")
            if stat.S_ISDIR(s.st_mode):
                entries[rel]=("dir",0,None)
                stack.extend(p.iterdir())
            elif stat.S_ISREG(s.st_mode):
                total+=s.st_size
                require(total<=MAX_BYTES,"BACKUP_SIZE_LIMIT")
                entries[rel]=("file",s.st_size,sha(p))
                links.setdefault((s.st_dev,s.st_ino),[s.st_nlink,0])[1]+=1
            else: raise Refused("UNSUPPORTED_DATA_TYPE")
    require(all(a==b for a,b in links.values()),"EXTERNAL_HARDLINK")
    require(entries.get("db/core.sqlite",("",0,None))[0]=="file","DATABASE_MISSING")
    return entries,total

def create_backup(state, dest, uid, slot):
    root_dir(dest,private=True)
    existing=list(dest.iterdir())
    require(len(existing)<MAX_BACKUPS,"BACKUP_RETENTION_LIMIT")
    require(all(p.is_dir() and not p.is_symlink() and re.fullmatch(r"backup-[0-9]+-[a-z0-9_]+",p.name) for p in existing),"BACKUP_STORE_UNEXPECTED")
    entries,total=inventory(state,uid)
    require(shutil.disk_usage(dest).free>=total+2*GIB+len(entries)*4096,"BACKUP_DISK_MARGIN")
    tmp=Path(tempfile.mkdtemp(prefix=".partial-",dir=dest))
    published=False
    try:
        arc=tmp/"state.tar"
        with tarfile.open(arc,"x",dereference=True) as t:
            # inventory already rejects symlinks and checks internal hardlinks.
            for rel in sorted(entries):
                t.add(state/rel,arcname=rel,recursive=False)
        with tarfile.open(arc,"r") as t:
            seen=set()
            for m in t:
                require(m.name in entries and m.name not in seen,"ARCHIVE_MEMBER_MISMATCH")
                seen.add(m.name)
                kind,size,digest=entries[m.name]
                if kind=="dir": require(m.isdir(),"ARCHIVE_TYPE_MISMATCH")
                else:
                    require(m.isfile() and m.size==size,"ARCHIVE_SIZE_MISMATCH")
                    with t.extractfile(m) as f:
                        require(hashlib.file_digest(f,"sha256").hexdigest()==digest,"ARCHIVE_DIGEST_MISMATCH")
            require(seen==set(entries),"ARCHIVE_INCOMPLETE")
        require(inventory(state,uid)==(entries,total),"DATA_CHANGED_DURING_BACKUP")
        manifest={"format":1,"scope":"quiescent data only; no credentials; not a restore authorization",
                  "slot":str(slot.name),"bytes":total,"entries":len(entries),
                  "archive_sha256":sha(arc),"inventory":entries}
        mf=tmp/"manifest.json"
        mf.write_text(json.dumps(manifest,sort_keys=True))
        for p in (arc,mf):
            p.chmod(0o600)
            with p.open("rb") as f: os.fsync(f.fileno())
        fd=os.open(tmp,os.O_DIRECTORY); os.fsync(fd); os.close(fd)
        final=dest/("backup-"+str(int(time.time()))+"-"+tmp.name.removeprefix(".partial-"))
        require(not final.exists(),"BACKUP_NAME_CONFLICT")
        tmp.rename(final); published=True
        fd=os.open(dest,os.O_DIRECTORY); os.fsync(fd); os.close(fd)
        return {"backup":"VERIFIED_LOCAL","entries":len(entries),"bytes":total}
    finally:
        if not published: shutil.rmtree(tmp)
    # No pruning or restore.

class Ops:
    def get(self,u):
        return props(command("/usr/bin/systemctl","--system","show","--all",u,*("-p"+p for p in PROPS)))

    def enrol_state(self):
        return command("/usr/bin/systemctl","--system","show",ENROL,"-p","LoadState","--value").decode().strip()

    def report(self):
        # No PID, paths, UUID, config, journal or tokens returned.
        result={u: {k:d[k] for k in ("LoadState","ActiveState","SubState","Result")}
                for u in PINS for d in (self.get(u),)}
        result[ENROL]={"LoadState":self.enrol_state()}
        return result

    def preflight(self):
        for u,digest in PINS.items():
            d=self.get(u)
            require(d["LoadState"]=="loaded" and d["UnitFileState"]=="static" and d["NeedDaemonReload"]=="no","UNIT_DRIFT")
            require(d["FragmentPath"]=="/etc/systemd/system/"+u and d["DropInPaths"]==(DROP if u==HTTP else ""),"UNIT_PATH_DRIFT")
            require(d["Job"] in ("","0"),"UNIT_JOB_PENDING")
            require(git_blob(Path(d["FragmentPath"]))==digest,"UNIT_HASH_DRIFT")
        require(root_file(Path(DROP)).read_bytes()==DROP_BYTES,"DROPIN_DRIFT")
        require(self.enrol_state()=="not-found","ENROLMENT_ACTIVE_OR_INSTALLED")
        require(self.get(ACL)["ActiveState"]=="active","ACL_NOT_ACTIVE")
        validate_acl(json.loads(command("/usr/sbin/nft","-j","-n","list","table","inet","montara_pilot_v2"))["nftables"],
                     pwd.getpwnam("montara-pilot-ingress").pw_uid)
        cur=BASE/"current"
        require(cur.is_symlink() and cur.lstat().st_uid==0 and cur.resolve()==SLOT,"SLOT_DRIFT")
        root_dir(SLOT)
        require(sha(root_file(BASE/"input/montara_core-0.1.0-py3-none-any.whl"))==
                "c7e11118d2d1c5bffe658b3ed2ef11ed8101e47e6ef027bd6a601c442bb8304f","WHEEL_DRIFT")
        require(sha(root_file(BASE/"ingress/cloudflared"))==
                "56f13335143ec0e22772963290683a84a04114a35ec64cbc794a4d39ff9bb8cf","CONNECTOR_DRIFT")
        d=tomllib.loads(root_file(CFG).read_text())
        require(d["http"]["port"]==8080 and d["pilot"]["renderer_root"]==str(SLOT/"renderer-src")
                and d["pilot"]["engine_root"]==str(SLOT/"engine-src"),"CONFIG_DRIFT")
        require(d["storage"]=={k:str(STATE/p) for k,p in (("sqlite_path","db/core.sqlite"),("media_root","originals"),("workspace_root","attempts"),("artifact_root","artifacts"))},"STORAGE_DRIFT")
        subjects=d["pilot"]["allowed_subjects"]
        require(isinstance(subjects,list) and len(subjects)==4 and len(set(subjects))==4,"ADMISSION_NOT_FOUR")
        origin=d["oidc"]["public_origin"]
        require(re.fullmatch(r"https://[a-z0-9-]+\.[a-z0-9-]+\.workers\.dev",origin) is not None,"ORIGIN_DRIFT")
        self.host=origin.removeprefix("https://")
        require(self.get(WORKER)["ActiveState"] in ("inactive","failed"),"WORKER_ACTIVE")
        self.check_quiet(WORKER)

    def check_quiet(self,u, previous=""):
        d=self.get(u)
        require(quiet(d),"UNIT_NOT_QUIESCENT")
        for cg in {previous,d["ControlGroup"],"/system.slice/"+u}-{""}:
            require(cg.startswith("/system.slice/") and ".." not in cg,"CGROUP_PATH_INVALID")
            p=Path("/sys/fs/cgroup"+cg+"/cgroup.events")
            if p.exists(): require("populated 0" in p.read_text().splitlines(),"CGROUP_NOT_EMPTY")

    def stop_one(self,u):
        old=self.get(u)["ControlGroup"]
        command("/usr/bin/systemctl","--system","stop",u,timeout=30)
        self.check_quiet(u,old)

    def start_one(self,u):
        command("/usr/bin/systemctl","--system","start",u,timeout=30)
        require(self.get(u)["ActiveState"]=="active","UNIT_NOT_ACTIVE")

    def listeners(self, running):
        raw=command("/usr/bin/ss","-H","-ltn").decode()
        found=[l.split()[3] for l in raw.splitlines() if l.split()[3].rsplit(":",1)[-1] in ("8080","20246")]
        require(sorted(found)==(sorted(["127.0.0.1:8080","127.0.0.1:20246"]) if running else []),"LISTENER_DRIFT")

    def no_processes(self):
        # Only dedicated V2 UIDs. No output of PID/args.
        uids={pwd.getpwnam(n).pw_uid for n in ("montara-pilot","montara-pilot-ingress","montara-pilot-enrol")}
        for p in Path("/proc").iterdir():
            if p.name.isdigit():
                try: s=(p/"status").read_text()
                except FileNotFoundError: continue
                line=next((x for x in s.splitlines() if x.startswith("Uid:")), "")
                if line: require(not (set(map(int,line.split()[1:])) & uids),"DEDICATED_UID_BUSY")

    def health(self):
        for _ in range(15):
            try:
                raw=command("/usr/sbin/runuser","-u","montara-pilot-ingress","--",
                    "/usr/bin/curl","--noproxy","*","-fsS","--max-time","2","-H",
                    "Host: "+self.host,"http://127.0.0.1:8080/health",timeout=4)
                if json.loads(raw)=={"status":"ok"}: return
            except (Refused,ValueError): pass
            time.sleep(1)
        raise Refused("HTTP_HEALTH_NOT_READY")

    def stop(self):
        # No new worker can enter via cooperating launcher while holding shared lock.
        self.stop_one(INGRESS)
        self.stop_one(HTTP)
        self.check_quiet(WORKER)
        self.listeners(False)
        self.no_processes()
        return {"admission":"CLOSED_LOCAL"}

    def start(self):
        for u in (INGRESS,HTTP,WORKER): self.check_quiet(u)
        require(all(self.get(u)["ActiveState"]=="inactive" for u in (INGRESS,HTTP)),"SERVICE_FAILED_REVIEW")
        require(safe_worker(self.get(WORKER)),"WORKER_REVIEW_REQUIRED")
        self.listeners(False)
        self.no_processes()
        try:
            self.start_one(HTTP)
            self.health()
            self.start_one(INGRESS)
            # connector metrics listener may need a short readiness interval.
            for _ in range(15):
                try: self.listeners(True); break
                except Refused: time.sleep(1)
            else: raise Refused("LOCAL_LISTENERS_NOT_READY")
        except BaseException:
            # Close only these two units, which were inactive before start.
            try: self.stop()
            except BaseException: raise Refused("START_FAILED_CLOSURE_UNVERIFIED") from None
            raise Refused("START_FAILED_CLOSED_LOCAL") from None
        return {"admission":"LOCAL_READY_EXTERNAL_GATE_REQUIRED"}

    def backup(self):
        for u in (INGRESS,HTTP,WORKER): self.check_quiet(u)
        require(safe_worker(self.get(WORKER)),"WORKER_REVIEW_REQUIRED")
        self.listeners(False); self.no_processes()
        uid=pwd.getpwnam("montara-pilot").pw_uid
        return create_backup(STATE,BACKUPS,uid,SLOT)

    def perform(self,action):
        require(action in ACTIONS,"UNKNOWN_ACTION")
        if action=="status": return self.report()
        self.preflight()
        if action=="restart":
            self.stop()
            self.preflight()
            return self.start()
        return getattr(self,action)()

def main():
    os.umask(0o077)
    os.chdir("/")
    syslog.openlog("montara-v2-ops")
    action=sys.argv[1] if len(sys.argv)==2 and sys.argv[1] in ACTIONS else "invalid"
    try:
        require(os.geteuid()==0 and os.environ.get("SUDO_USER")=="sentinelx","OPERATOR_BOUNDARY")
        require(action in ACTIONS,"UNKNOWN_ACTION")
        with exclusive():
            result=Ops().perform(action)
        syslog.syslog(syslog.LOG_NOTICE,"action="+action+" result=ok")
        print(json.dumps({"action":action,"result":result},sort_keys=True))
        return 0
    except Refused as e:
        code=str(e)
    except (Exception,KeyboardInterrupt):
        code="UNEXPECTED_REVIEW_REQUIRED"
    syslog.syslog(syslog.LOG_WARNING,"action="+action+" result="+code)
    print(json.dumps({"action":action,"result":code}))
    return 1

if __name__=="__main__": sys.exit(main())
