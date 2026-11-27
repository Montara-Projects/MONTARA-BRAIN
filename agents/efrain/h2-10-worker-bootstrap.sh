#!/bin/bash
# H2.10 operator bootstrap; explicit FER authorization, no worker start here.
set -Eeuo pipefail
umask 077
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
unset PYTHONPATH PYTHONHOME BASH_ENV ENV
agent=sentinelx-cloud-core.service
unit=montara-pilot-worker.service
cfg=/etc/sentinelx/config.yaml
rule=/etc/polkit-1/rules.d/49-montara-pilot-worker.rules
start=/usr/local/bin/montara-pilot-worker-start
status=/usr/local/bin/montara-pilot-worker-status
admin=/var/lib/montara-worker-delegation
slot=/opt/montara-pilot/releases/c7e11118d2d1
state=/var/lib/montara-pilot
phase=preflight
armed=0
cfg_changed=0
test "$(id -u)" = 0
test "$#" -eq 1
mode=$1
mark() { phase=$1; printf 'PHASE=%s\n' "$phase"; }
hashgit() { test "$(git hash-object --no-filters "$1")" = "$2"; }
root_file() { test -f "$1" && test ! -L "$1" && test "$(stat -c %u "$1")" = 0 && test "$((8#$(stat -c %a "$1") & 022))" = 0; }
# Verify an actual agent process subject, queried by root, no interaction.
subject() {
    pid=$(systemctl show "$agent" -p MainPID --value)
    uid=$(id -u sentinelx)
    test "$pid" -gt 1 && test "$uid" -ne 0
    test "$(ps -o euid= -p "$pid" | tr -d ' ')" = "$uid"
    ticks=$(/usr/bin/python3 -I -c 'import sys; print(open("/proc/"+sys.argv[1]+"/stat").read().rsplit(")",1)[1].split()[19])' "$pid")
    subj="$pid,$ticks,$uid"
}
check_auth() {
    local expected=$1 action=$2 u=$3 verb=$4 rc=0
    pkcheck --action-id "$action" --process "$subj" --detail unit "$u" --detail verb "$verb" >/dev/null 2>&1 || rc=$?
    if test "$expected" = 0; then test "$rc" = 0; else test "$rc" = 1 || test "$rc" = 2; fi
}
negative() {
    local a=org.freedesktop.systemd1.manage-units
    check_auth 1 "$a" "$unit" stop
    check_auth 1 "$a" "$unit" restart
    check_auth 1 "$a" montara-pilot-http.service start
    check_auth 1 "$a" montara-pilot-ingress.service start
    check_auth 1 "$a" "$unit" reload
    check_auth 1 org.freedesktop.systemd1.manage-unit-files "$unit" enable
    check_auth 1 org.freedesktop.systemd1.reload-daemon "$unit" reload
}
# Change only the two exact YAML list items, preserving all other bytes.
# PyYAML verifies semantic equality; never overwrite a concurrent config edit.
edit_cfg() {
    /usr/bin/python3 -I - "$cfg" "$1" "$start" "$status" <<'PY'
import os, re, stat, sys, tempfile
import yaml
p,mode,*new=sys.argv[1:]
with open(p,'rb') as f:
    raw=f.read()
    st=os.fstat(f.fileno())
assert stat.S_ISREG(st.st_mode) and st.st_uid==0 and not st.st_mode&0o022
s=raw.decode('utf-8')
old=yaml.safe_load(s)
assert isinstance(old,dict) and isinstance(old['allowed_commands'],list)
assert all(isinstance(x,str) for x in old['allowed_commands'])
assert old.get('exec_mode', 'strict' if old.get('exec_strict') is True else None)=='strict'
lines=s.splitlines(keepends=True)
if mode=='add':
    assert old['allowed_commands']==['uptime','free -h','df -h','id','/usr/local/bin/montara-test']
    hits=[i for i,l in enumerate(lines) if re.fullmatch(r'([ \t]*)-[ \t]+(?:"/usr/local/bin/montara-test"|\'/usr/local/bin/montara-test\'|/usr/local/bin/montara-test)[ \t]*(?:#[^\n]*)?\n',l)]
    assert len(hits)==1
    i=hits[0]; indent=re.match(r'[ \t]*',lines[i]).group()
    lines[i+1:i+1]=[indent+'- '+v+'\n' for v in new]
    wanted=old['allowed_commands']+new
elif mode=='remove':
    wanted=[v for v in old['allowed_commands'] if v not in new]
    assert all(old['allowed_commands'].count(v)==1 for v in new)
    for v in new:
        hits=[i for i,l in enumerate(lines) if re.fullmatch(r'[ \t]*-[ \t]+'+re.escape(v)+r'[ \t]*\n',l)]
        assert len(hits)==1
        del lines[hits[0]]
else: raise ValueError('mode')
out=''.join(lines)
old['allowed_commands']=wanted
assert yaml.safe_load(out)==old
fd,tmp=tempfile.mkstemp(prefix='.montara-worker-',dir=os.path.dirname(p))
try:
    with os.fdopen(fd,'wb') as f:
        f.write(out.encode()); f.flush(); os.fsync(f.fileno())
        os.fchown(f.fileno(),st.st_uid,st.st_gid); os.fchmod(f.fileno(),stat.S_IMODE(st.st_mode))
    with open(p,'rb') as f:
        assert f.read()==raw
        assert os.fstat(f.fileno()).st_ino==st.st_ino
    os.replace(tmp,p)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
}
restore_cfg() {
    # Bootstrap rollback only: don't clobber unrelated later changes.
    if test -f "$admin/private/config.after"; then
        if cmp -s "$cfg" "$admin/private/config.after"; then
            local tmp
            tmp=$(mktemp -d "$(dirname "$cfg")/.rollback-montara.XXXXXXXX")
            cp -a "$admin/private/config.before" "$tmp/config"
            mv -T "$tmp/config" "$cfg"
            rmdir "$tmp"
        elif ! cmp -s "$cfg" "$admin/private/config.before"; then
            edit_cfg remove || return 1
        fi
    elif ! cmp -s "$cfg" "$admin/private/config.before"; then
        edit_cfg remove || return 1
    fi
}
rollback() {
    local fail=0
    rm -f -- "$rule" || fail=1
    if test "$cfg_changed" = 1; then
        restore_cfg || fail=1
        systemctl restart "$agent" >/dev/null 2>&1 || fail=1
        systemctl is-active --quiet "$agent" || fail=1
    fi
    rm -f -- "$start" "$status" || fail=1
    if subject; then
        for n in {1..15}; do
            if check_auth 1 org.freedesktop.systemd1.manage-units "$unit" start; then break; fi
            sleep 1
        done
    else fail=1; fi
    if test "$fail" = 0 && check_auth 1 org.freedesktop.systemd1.manage-units "$unit" start; then
        echo WORKER_GRANT_REVOKED=PASS
    else fail=1; fi
    if test "$fail" = 0; then echo BOOTSTRAP_ROLLBACK=PASS; else echo BOOTSTRAP_ROLLBACK=REVIEW_REQUIRED; fi
}
finish() {
    local rc=$?
    trap - EXIT ERR
    if test "$rc" != 0; then
        printf 'BOOTSTRAP_FAILED_PHASE=%s RC=%s\n' "$phase" "$rc"
        if test "$armed" = 1; then rollback; fi
        echo FIXTURE_IF_CREATED_PRESERVED
    fi
    exit "$rc"
}
trap finish EXIT
trap 'printf "ERROR_LINE=%s\n" "$LINENO"' ERR
if test "$mode" = revoke; then
    mark revoke
    root_file "$admin/bootstrap.sh"
    # Only our files; preserve other configuration and all pilot data.
    test -f "$admin/private/config.before"
    rm -f -- "$rule"
    subject
    for n in {1..15}; do
        if check_auth 1 org.freedesktop.systemd1.manage-units "$unit" start; then break; fi
        sleep 1
    done
    check_auth 1 org.freedesktop.systemd1.manage-units "$unit" start
    echo WORKER_GRANT_REVOKED=PASS
    edit_cfg remove
    rm -f -- "$start" "$status"
    systemctl restart "$agent" >/dev/null 2>&1
    systemctl is-active --quiet "$agent"
    subject
    check_auth 1 org.freedesktop.systemd1.manage-units "$unit" start
    negative
    echo DELEGATION_REVOKED=PASS
    exit 0
fi
test "$mode" = install
for cmd in git pkcheck flock runuser systemctl python3; do command -v "$cmd" >/dev/null; done
/usr/bin/python3 -I -c 'import yaml'
systemctl is-active --quiet polkit.service
systemctl is-active --quiet "$agent"
root_file "$cfg"
for p in "$rule" "$start" "$status" "$admin"; do test ! -e "$p" && test ! -L "$p"; done
test -d /etc/polkit-1/rules.d
test "$(realpath /opt/montara-pilot/current)" = "$slot"
test -L /opt/montara-pilot/current && test "$(stat -c %u /opt/montara-pilot/current)" = 0
test "$(stat -c '%U:%G:%a' "$slot")" = root:montara-pilot:750
for u in montara-pilot-http montara-pilot-ingress montara-pilot-acl; do systemctl is-active --quiet "$u.service"; done
test "$(systemctl show montara-pilot-enrol.service -p LoadState --value)" = not-found
test "$(systemctl show "$unit" -p ActiveState --value)" = inactive
test "$(systemctl show "$unit" -p MainPID --value)" = 0
test "$(systemctl show "$unit" -p Result --value)" = success
test "$(systemctl show "$unit" -p FragmentPath --value)" = "/etc/systemd/system/$unit"
test -z "$(systemctl show "$unit" -p DropInPaths --value)"
test "$(systemctl show "$unit" -p NeedDaemonReload --value)" = no
systemctl --help | grep -- "--wait" >/dev/null
root_file "/etc/systemd/system/$unit"
hashgit "/etc/systemd/system/$unit" 6d9df7806b9567aa5fef4467f6984ef69f26af30
root_file "$slot/renderer-src/tools/core_v2_media_fixture.py"
root_file "$slot/renderer-src/tests/fixtures/core-v2/stage-recipe-v1.json"
hashgit "$slot/renderer-src/tools/core_v2_media_fixture.py" d2c8e42b461868d11ead0c306430ecbad45bff64
hashgit "$slot/renderer-src/tests/fixtures/core-v2/stage-recipe-v1.json" c02fadd61275cfbab1a1727eb4e551f4790e1506
printf '%s  %s\n' ed16af623947494a72e284b6eb8ff225f2da22b38b5d5069c2fd4b4ba3384e41 "$slot/ffmpeg-root/usr/bin/ffmpeg" 272f6ebc634a63d9c8b4ca68e964119d980f25154e5aa2c35e5487da48e9a58f "$slot/ffmpeg-root/usr/bin/ffprobe" | sha256sum -c --status
subject
check_auth 1 org.freedesktop.systemd1.manage-units "$unit" start
negative
# Confirm config exact shape before any mutation (semantic and editable line).
/usr/bin/python3 -I - "$cfg" <<'PY'
import sys,yaml,re
s=open(sys.argv[1]).read()
d=yaml.safe_load(s)
assert d.get('exec_mode', 'strict' if d.get('exec_strict') is True else None)=='strict'
assert d['allowed_commands']==['uptime','free -h','df -h','id','/usr/local/bin/montara-test']
assert len(re.findall(r'^[ \t]*-[ \t]+(?:"/usr/local/bin/montara-test"|\'/usr/local/bin/montara-test\'|/usr/local/bin/montara-test)[ \t]*(?:#[^\n]*)?$',s,re.M))==1
PY
echo PREFLIGHT=PASS
mark fixture
echo 'Selecciona en la UI un proyecto propio YA EXISTENTE. No registres ni solicites render durante este bloque.'
read -r -s -p 'UUID de ese proyecto (entrada privada): ' project
echo
# UUID comes only from FER's current authenticated UI, not from DB discovery.
fixture_py=$(cat <<'PY'
import hashlib, importlib.util, os, shutil, stat, sys
from pathlib import Path
from montara_core.domain.projects import validate_id
slot,state=sys.argv[1:]
project=sys.stdin.readline().strip()
validate_id(project)
slot,state=Path(slot),Path(state)
os.umask(0o077)
uid=os.getuid()
def private_dir(p):
    st=p.lstat()
    assert stat.S_ISDIR(st.st_mode) and st.st_uid==uid and stat.S_IMODE(st.st_mode)==0o700 and p.resolve()==p
for p in (state,state/'originals',state/'runtime-home',state/'db',state/'attempts',state/'artifacts'):
    private_dir(p)
    assert shutil.disk_usage(p).free>=2*1024**3
spec=importlib.util.spec_from_file_location('fixture',slot/'renderer-src/tools/core_v2_media_fixture.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
bank=state/'runtime-home'/'human-qa-fixture-v1'
if bank.exists() or bank.is_symlink(): private_dir(bank)
else: m.generate(bank)
manifest=m.verify_inputs(bank)
names=('camera-a.mp4','camera-b.mp4','master.wav')
rows={r['path']:r for r in manifest['files'] if r['path'] in names}
assert set(rows)==set(names) and sum(r['bytes'] for r in rows.values())<=512*1024**2
for name in names:
    r=rows[name]; p=bank/name
    assert 0<r['bytes']<=256*1024**2
    probe=m.probe(p); streams=probe['streams']
    assert abs(float(probe['format']['duration'])-6)<=0.15
    if name.endswith('.mp4'):
        v=[s for s in streams if s['codec_type']=='video']
        a=[s for s in streams if s['codec_type']=='audio']
        assert len(v)==len(a)==1 and v[0]['codec_name']=='h264' and (v[0]['width'],v[0]['height'])==(640,360) and v[0]['r_frame_rate']=='30/1' and a[0]['codec_name']=='aac'
        m.decode(p)
    else:
        assert len(streams)==1 and streams[0]['codec_name']=='pcm_s16le' and streams[0]['sample_rate']=='48000' and streams[0]['channels']==1
dest=state/'originals'/project
def verify():
    private_dir(dest)
    assert set(p.name for p in dest.iterdir())==set(names)
    for n in names:
        p=dest/n; st=p.lstat()
        assert stat.S_ISREG(st.st_mode) and st.st_uid==uid and stat.S_IMODE(st.st_mode)==0o600
        assert st.st_size==rows[n]['bytes'] and m.sha256(p)==rows[n]['sha256']
if dest.exists() or dest.is_symlink():
    verify()
else:
    dest.mkdir(mode=0o700)
    fd=os.open(dest,os.O_DIRECTORY|os.O_NOFOLLOW|os.O_RDONLY)
    try:
        for n in names:
            with (bank/n).open('rb') as src:
                out=os.open(n,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=fd)
                with os.fdopen(out,'wb') as dst:
                    shutil.copyfileobj(src,dst); dst.flush(); os.fsync(dst.fileno())
        os.fsync(fd)
    finally: os.close(fd)
    verify()
for n in names: print('FIXTURE',n,rows[n]['bytes'],rows[n]['sha256'])
print('FIXTURE_READY=PASS')
PY
)
printf '%s\n' "$project" | runuser -u montara-pilot -- env -i HOME="$state/runtime-home" PATH="$slot/media-tools:/usr/bin:/bin" "$slot/pilot-runtime/venv/bin/python" -I -B -c "$fixture_py" "$slot" "$state"
unset project fixture_py
mark delegation
# No command from the test queue is executed here.
install -d -o root -g root -m 0755 "$admin"
install -d -o root -g root -m 0700 "$admin/private"
cp -a "$cfg" "$admin/private/config.before"
install -o root -g root -m 0700 "$0" "$admin/bootstrap.sh"
install -o root -g root -m 0444 /dev/null "$admin/worker.lock"
armed=1
cat > "$status" <<'STATUS'
#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin LC_ALL=C
unset BASH_ENV ENV PYTHONPATH PYTHONHOME
test "$#" = 0
test "$(id -un)" = sentinelx
exec systemctl show montara-pilot-worker.service -p ActiveState -p SubState -p Result -p ExecMainCode -p ExecMainStatus -p MainPID
STATUS
cat > "$start" <<'START'
#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin LC_ALL=C
test "$#" = 0
test "$(id -un)" = sentinelx
unit=montara-pilot-worker.service
exec 9</var/lib/montara-worker-delegation/worker.lock
flock -n 9 || { echo WORKER_INVOCATION_BUSY; exit 3; }
test "$(git hash-object --no-filters "/etc/systemd/system/$unit")" = 6d9df7806b9567aa5fef4467f6984ef69f26af30
test "$(systemctl show "$unit" -p FragmentPath --value)" = "/etc/systemd/system/$unit"
test -z "$(systemctl show "$unit" -p DropInPaths --value)"
test "$(systemctl show "$unit" -p NeedDaemonReload --value)" = no
test "$(systemctl show "$unit" -p ActiveState --value)" = inactive
test "$(systemctl show "$unit" -p MainPID --value)" = 0
test "$(systemctl show "$unit" -p Result --value)" = success
rc=0
timeout 650s systemctl --no-ask-password --wait start "$unit" >/dev/null 2>&1 || rc=$?
/usr/local/bin/montara-pilot-worker-status
printf 'WORKER_SYSTEMCTL_RC=%s\n' "$rc"
test "$rc" = 0
test "$(systemctl show "$unit" -p ActiveState --value)" = inactive
test "$(systemctl show "$unit" -p MainPID --value)" = 0
test "$(systemctl show "$unit" -p Result --value)" = success
test "$(systemctl show "$unit" -p ExecMainCode --value)" = 1
test "$(systemctl show "$unit" -p ExecMainStatus --value)" = 0
echo WORKER_CYCLE_EXIT_ZERO
START
chmod 0755 "$start" "$status"
root_file "$start"; root_file "$status"
bash -n "$start"; bash -n "$status"
runuser -u sentinelx -- "$status"
if runuser -u sentinelx -- "$start" unexpected >/dev/null 2>&1; then exit 1; fi
if runuser -u sentinelx -- "$status" unexpected >/dev/null 2>&1; then exit 1; fi
cat > "$rule" <<'RULE'
polkit.addRule(function(action, subject) {
    if (subject.user === "sentinelx" &&
        action.id === "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") === "montara-pilot-worker.service" &&
        action.lookup("verb") === "start") {
        return polkit.Result.YES;
    }
});
RULE
chmod 0644 "$rule"
root_file "$rule"
for n in {1..15}; do
    if check_auth 0 org.freedesktop.systemd1.manage-units "$unit" start; then break; fi
    sleep 1
done
check_auth 0 org.freedesktop.systemd1.manage-units "$unit" start
negative
echo POLKIT_EXACT_START_AND_NEGATIVES=PASS
mark reconnect
cfg_changed=1
edit_cfg add
cp -a "$cfg" "$admin/private/config.after"
systemctl restart "$agent" >/dev/null 2>&1
systemctl is-active --quiet "$agent"
subject
check_auth 0 org.freedesktop.systemd1.manage-units "$unit" start
negative
runuser -u sentinelx -- "$status"
test "$(systemctl show "$unit" -p ActiveState --value)" = inactive
for u in montara-pilot-http montara-pilot-ingress montara-pilot-acl; do systemctl is-active --quiet "$u.service"; done
armed=0
echo WORKER_NOT_STARTED=PASS
echo BOOTSTRAP_LOCAL=PASS
echo 'Revocar: sudo /var/lib/montara-worker-delegation/bootstrap.sh revoke'
