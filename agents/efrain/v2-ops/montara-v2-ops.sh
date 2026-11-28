#!/bin/bash
# Executed as sentinelx, never source files from the workspace.
set -euo pipefail
test "$#" = 1
test "$(/usr/bin/id -un)" = sentinelx
case "$1" in status|start|stop|restart|backup) ;; *) exit 2 ;; esac
exec /usr/bin/sudo -n -- /usr/local/sbin/montara-v2-ops-root "$1"
