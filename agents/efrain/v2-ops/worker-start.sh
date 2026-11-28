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
# One coherent snapshot, not six independent queries after GC.
snapshot=$(/usr/local/bin/montara-pilot-worker-status) || { echo WORKER_STATUS_UNAVAILABLE; exit 1; }
printf '%s\n' "$snapshot"
printf 'WORKER_SYSTEMCTL_RC=%s\n' "$rc"
classify() {
    local rc=$1 snapshot=$2 pair
    test "$rc" = 0 || return 1
    test "$(printf '%s\n' "$snapshot" | wc -l)" = 6 || return 1
    for p in ActiveState=inactive SubState=dead MainPID=0 Result=success ExecMainStatus=0; do
        test "$(printf '%s\n' "$snapshot" | grep -Fxc "$p")" = 1 || return 1
    done
    pair=$(printf '%s\n' "$snapshot" | grep -E '^ExecMainCode=[01]$') || return 1
    case "$pair" in
        ExecMainCode=1) echo WORKER_CYCLE_EXIT_ZERO ;;
        ExecMainCode=0) echo WORKER_CYCLE_EXIT_METADATA_UNAVAILABLE ;;
        *) return 1 ;;
    esac
}
classify "$rc" "$snapshot" || { echo WORKER_CYCLE_REVIEW_REQUIRED; exit 1; }
# In either branch, Core publication is an independent gate. No retry.
