#!/bin/bash
# Candidate bootstrap only. Do not run until Alfred/QA approve exact combined scope.
set -Eeuo pipefail
umask 077
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
unset BASH_ENV ENV PYTHONPATH PYTHONHOME
test "$(id -u)" = 0
test "$#" = 1
mode=$1
D=$(dirname "$(realpath "$0")")
cfg=/etc/sentinelx/config.yaml
agent=sentinelx-cloud-core.service
admin=/var/lib/montara-v2-ops
backup=/var/lib/montara-v2-backups
policy=/etc/sudoers.d/90-montara-v2-ops
helper=/usr/local/sbin/montara-v2-ops-root
wrapper=/usr/local/bin/montara-v2-ops
worker=/usr/local/bin/montara-pilot-worker-start
bank=/opt/montara-pilot/fixture-bank-v1
lock=/var/lib/montara-worker-delegation/worker.lock
phase=preflight
armed=0
changed_cfg=0
changed_worker=0
mark() { phase=$1; echo "PHASE=$phase"; }
rootfile() { test -f "$1" && test ! -L "$1" && test "$(stat -c %u "$1")" = 0 && (( (8#$(stat -c %a "$1") & 022) == 0 )); }
rootdir() { test -d "$1" && test ! -L "$1" && test "$(stat -c %u "$1")" = 0 && (( (8#$(stat -c %a "$1") & 022) == 0 )); }
hashgit() { rootfile "$1"; test "$(git hash-object --no-filters "$1")" = "$2"; }
permit() { sudo -n -l -U sentinelx -- "$helper" "$1" >/dev/null 2>&1; }
denied() {
    local rc=0
    sudo -n -l -U sentinelx -- "$@" >/dev/null 2>&1 || rc=$?
    test "$rc" = 1
}
negative() {
    denied /bin/sh
    denied /usr/bin/true
    denied /usr/bin/systemctl restart montara-pilot-http.service
    denied "$helper" restore
    denied "$helper" status extra
    denied "$helper"
}
edit_cfg() {
    /usr/bin/python3 -I - "$cfg" "$1" "$wrapper" <<'PY'
import os,re,stat,sys,tempfile,yaml
p,mode,new=sys.argv[1:]
with open(p,'rb') as f:
    raw=f.read(); st=os.fstat(f.fileno())
assert stat.S_ISREG(st.st_mode) and st.st_uid==0 and not st.st_mode&0o022
s=raw.decode()
d=yaml.safe_load(s)
assert d.get('exec_mode','strict' if d.get('exec_strict') is True else None)=='strict'
old=d['allowed_commands']
expected=['uptime','free -h','df -h','id','/usr/local/bin/montara-test',
          '/usr/local/bin/montara-pilot-worker-start','/usr/local/bin/montara-pilot-worker-status']
lines=s.splitlines(keepends=True)
if mode=='add':
    assert old==expected
    hits=[i for i,l in enumerate(lines) if re.fullmatch(r'([ \t]*)-[ \t]+(?:"/usr/local/bin/montara-pilot-worker-status"|\'/usr/local/bin/montara-pilot-worker-status\'|/usr/local/bin/montara-pilot-worker-status)[ \t]*(?:#[^\n]*)?\n',l)]
    assert len(hits)==1
    i=hits[0]; indent=re.match(r'[ \t]*',lines[i]).group()
    lines[i+1:i+1]=[indent+'- '+new+'\n']
    d['allowed_commands']=old+[new]
elif mode=='remove':
    assert old.count(new)<=1
    if new not in old: sys.exit(0)
    hits=[i for i,l in enumerate(lines) if re.fullmatch(r'[ \t]*-[ \t]+'+re.escape(new)+r'[ \t]*\n',l)]
    assert len(hits)==1
    del lines[hits[0]]
    d['allowed_commands']=[v for v in old if v!=new]
else: raise ValueError('mode')
out=''.join(lines)
assert yaml.safe_load(out)==d
fd,tmp=tempfile.mkstemp(prefix='.montara-ops-',dir=os.path.dirname(p))
try:
    with os.fdopen(fd,'wb') as f:
        f.write(out.encode()); f.flush(); os.fsync(f.fileno())
        os.fchown(f.fileno(),st.st_uid,st.st_gid); os.fchmod(f.fileno(),stat.S_IMODE(st.st_mode))
    with open(p,'rb') as f:
        assert f.read()==raw and os.fstat(f.fileno()).st_ino==st.st_ino
    os.replace(tmp,p)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
}
revoke_grant() {
    # First revoke capability; no service stops, no data deletion.
    rm -f -- "$policy"
    visudo -c >/dev/null 2>&1 || return 1
    for a in status start stop restart backup; do denied "$helper" "$a" || return 1; done
}
rollback() {
    local fail=0
    revoke_grant || fail=1
    if test "$changed_cfg" = 1; then
        edit_cfg remove || fail=1
        systemctl restart "$agent" >/dev/null 2>&1 || fail=1
        systemctl is-active --quiet "$agent" || fail=1
    fi
    rm -f -- "$wrapper" "$helper" || fail=1
    if test "$changed_worker" = 1; then
        if flock -n 9; then
            if cmp -s "$worker" "$admin/worker.after"; then
                install -o root -g root -m 0755 "$admin/worker.before" "$worker" || fail=1
            else fail=1; fi
        else fail=1; fi
    fi
    # Immutable synthetic bank, backups and private backup of policy are preserved.
    if test "$fail" = 0; then echo OPS_ROLLBACK=PASS; else echo OPS_ROLLBACK_REVIEW_REQUIRED; fi
}
finish() {
    local rc=${1:-$?}
    trap - EXIT ERR
    if test "$rc" != 0; then
        echo "OPS_FAILED_PHASE=$phase RC=$rc"
        if test "$armed" = 1; then rollback; fi
    fi
    exit "$rc"
}
trap finish EXIT
trap 'echo "OPS_ERROR_LINE=$LINENO"' ERR
if test "$mode" = revoke; then
    mark revoke
    rootfile "$admin/activate.sh"
    revoke_grant
    exec 9<"$lock"
    flock -n 9 || { echo OPS_GRANT_REVOKED_BUT_OPERATION_BUSY; exit 1; }
    edit_cfg remove
    systemctl restart "$agent" >/dev/null 2>&1
    systemctl is-active --quiet "$agent"
    rm -f -- "$wrapper" "$helper"
    echo OPS_REVOKED_LOCAL=PASS
    # Existing one-shot worker permission and corrected launcher stay intact.
    # No backup/media removal and no new permissions.
    exit 0
fi
test "$mode" = install
rootdir "$D"
rootfile "$cfg"; rootfile "$worker"; rootfile "$lock"; rootdir "$(dirname "$lock")"
for p in "$admin" "$backup" "$policy" "$helper" "$wrapper" "$bank"; do test ! -e "$p" && test ! -L "$p"; done
hashgit "$D/ops.py" 4d377f3f96227683ee357edbbdfc995dae3eacf9
hashgit "$D/worker-start.sh" 32936861f034b95d95a6a5479b10456799737676
hashgit "$D/montara-v2-ops.sh" 2456351767d7a3356f18b30789fe691bf93d43de
hashgit "$D/sudoers" bc53e09a71130451fa2c93bf98be051b084f1609
bash -n "$D/worker-start.sh"; bash -n "$D/montara-v2-ops.sh"
visudo -c >/dev/null 2>&1
visudo -cf "$D/sudoers" >/dev/null 2>&1
/usr/bin/python3 -I -c 'import yaml'
systemctl is-active --quiet "$agent"
negative
for a in status start stop restart backup; do denied "$helper" "$a"; done
cmp -s "$worker" <(cat <<'PREVIOUS_WORKER'
#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin LC_ALL=C
test "$#" = 0
test "$(id -un)" = sentinelx
unit=montara-pilot-worker.service
systemctl() { /usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C /usr/bin/systemctl --system "$@"; }
exec 9</var/lib/montara-worker-delegation/worker.lock
flock -n 9 || { echo WORKER_INVOCATION_BUSY; exit 3; }
test "$(/usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C /usr/bin/git hash-object --no-filters "/etc/systemd/system/$unit")" = 6d9df7806b9567aa5fef4467f6984ef69f26af30
test "$(systemctl show "$unit" -p FragmentPath --value)" = "/etc/systemd/system/$unit"
test -z "$(systemctl show "$unit" -p DropInPaths --value)"
test "$(systemctl show "$unit" -p NeedDaemonReload --value)" = no
test "$(systemctl show "$unit" -p ActiveState --value)" = inactive
test "$(systemctl show "$unit" -p MainPID --value)" = 0
test "$(systemctl show "$unit" -p Result --value)" = success
rc=0
timeout 650s /usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C /usr/bin/systemctl --system --no-ask-password --wait start "$unit" >/dev/null 2>&1 || rc=$?
/usr/local/bin/montara-pilot-worker-status
printf 'WORKER_SYSTEMCTL_RC=%s\n' "$rc"
test "$rc" = 0
test "$(systemctl show "$unit" -p ActiveState --value)" = inactive
test "$(systemctl show "$unit" -p MainPID --value)" = 0
test "$(systemctl show "$unit" -p Result --value)" = success
test "$(systemctl show "$unit" -p ExecMainCode --value)" = 1
test "$(systemctl show "$unit" -p ExecMainStatus --value)" = 0
echo WORKER_CYCLE_EXIT_ZERO
PREVIOUS_WORKER
)
exec 9<"$lock"
flock -n 9
# No write in preflight; old deployment remains live.
 /usr/bin/python3 -I -B - "$D/ops.py" <<'PY'
import importlib.util,sys
s=importlib.util.spec_from_file_location("v2ops",sys.argv[1])
m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
o=m.Ops(); o.preflight()
m.require(m.safe_worker(o.get(m.WORKER)),"WORKER_NOT_CLEAN")
m.require(o.get(m.HTTP)["ActiveState"]=="active" and o.get(m.INGRESS)["ActiveState"]=="active","PILOT_NOT_ACTIVE")
o.listeners(True)
print("OPS_PREFLIGHT=PASS")
PY
# Copy only already verified synthetic bytes under the dedicated nonroot UID.
mark fixture_bank
T=$(mktemp -d /root/montara-bank.XXXXXXXX)
trap 'rc=$?; rm -rf -- "$T"; finish "$rc"' EXIT
for line in \
 'camera-a.mp4 63410 f290175c1fb7f2587baf6e535b0f6adde0ad78b2d31ec250ae027a0590abfbc7' \
 'camera-b.mp4 63194 2817a6ab4b4833f40a5eb9534a90c2c173d3affe408045594f54daa09d87674d' \
 'master.wav 576078 8ae3abdb2fef54830f15e0177af8daa92cfb8481564fc9822a9acee950eaf33e'; do
    read -r name size digest <<<"$line"
    runuser -u montara-pilot -- /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I - "$name" "$size" >"$T/$name" <<'PY'
import os,stat,sys
name,size=sys.argv[1],int(sys.argv[2])
assert name in ("camera-a.mp4","camera-b.mp4","master.wav")
d=os.open("/var/lib/montara-pilot/runtime-home/human-qa-fixture-v1",os.O_DIRECTORY|os.O_NOFOLLOW|os.O_RDONLY)
fd=os.open(name,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=d)
try:
    s=os.fstat(fd); assert stat.S_ISREG(s.st_mode) and s.st_uid==os.getuid() and s.st_size==size
    with os.fdopen(fd,"rb") as f:
        data=f.read(size+1)
        assert len(data)==size
        sys.stdout.buffer.write(data)
finally: os.close(d)
PY
    test "$(wc -c < "$T/$name")" = "$size"
    printf '%s  %s\n' "$digest" "$T/$name" | sha256sum -c --status
done
install -d -o root -g root -m 0700 "$admin" "$backup"
cp -a "$cfg" "$admin/config.before"
cp -a "$worker" "$admin/worker.before"
cp -a "$D/worker-start.sh" "$admin/worker.after"
install -o root -g root -m 0700 "$0" "$admin/activate.sh"
# Bank is published read-only to pilot; no originals directory mutation.
install -d -o root -g montara-pilot -m 0750 "$bank"
for n in camera-a.mp4 camera-b.mp4 master.wav; do
    install -o root -g montara-pilot -m 0440 "$T/$n" "$bank/$n"
    runuser -u montara-pilot -- test -r "$bank/$n"
    if runuser -u montara-pilot -- test -w "$bank/$n"; then exit 1; fi
done
if runuser -u montara-pilot -- test -w "$bank"; then exit 1; fi
echo IMMUTABLE_FIXTURE_BANK=PASS
rm -rf -- "$T"
trap finish EXIT
armed=1
mark delegation
install -o root -g root -m 0755 "$D/ops.py" "$helper"
install -o root -g root -m 0755 "$D/montara-v2-ops.sh" "$wrapper"
changed_worker=1
# Atomic replacement of only the reviewed launcher; same path and Polkit grant.
W=$(mktemp /usr/local/bin/.montara-worker.XXXXXXXX)
install -o root -g root -m 0755 "$D/worker-start.sh" "$W"
mv -T "$W" "$worker"
install -o root -g root -m 0440 "$D/sudoers" "$policy"
visudo -c >/dev/null 2>&1
for a in status start stop restart backup; do permit "$a"; done
negative
echo EXACT_SUDO_SCOPE=PASS
revoke_grant
negative
echo EXACT_SUDO_REVOCATION=PASS
install -o root -g root -m 0440 "$D/sudoers" "$policy"
visudo -c >/dev/null 2>&1
for a in status start stop restart backup; do permit "$a"; done
negative
changed_cfg=1
edit_cfg add
systemctl restart "$agent" >/dev/null 2>&1
systemctl is-active --quiet "$agent"
flock -u 9
# Real nonmutating exercise through the effective UID/sudo boundary.
runuser -u sentinelx -- "$wrapper" status
for a in status start stop restart backup; do permit "$a"; done
negative
armed=0
echo OPS_LOCAL_READY=PASS
echo 'Revocar nueva delegación: sudo /var/lib/montara-v2-ops/activate.sh revoke'
