#!/usr/bin/env bash
set -euo pipefail

# Android tooling connects to localhost:5037, while the real adb server runs on
# the host. Expose it through the Unix socket mounted from the host.
if [ -n "${ADB_BRIDGE_SOCKET:-}" ] && [ -S "$ADB_BRIDGE_SOCKET" ]; then
  socat TCP-LISTEN:5037,bind=127.0.0.1,fork,reuseaddr \
    UNIX-CONNECT:"$ADB_BRIDGE_SOCKET" &
fi

# The project references its JDK by name (.idea/misc.xml, .idea/gradle.xml).
# The container always provides the same JDK, so it is registered before the
# IDE reads the SDK table; otherwise Gradle sync fails with "JDK not found".
/usr/local/bin/jdk-table.sh || true

# Run the IDE as a child so the container survives its own restart, which the
# IDE performs after a license is activated.
"$@" &
ide_pid=$!
trap 'kill -TERM "$ide_pid" 2>/dev/null || true' TERM INT
wait "$ide_pid" || true

# Keep the container alive while a restarted IDE runs.
grace=20
while [ "$grace" -gt 0 ]; do
  if pgrep -f "com.intellij.idea.Main" >/dev/null 2>&1; then
    grace=20
  else
    grace=$((grace - 2))
  fi
  sleep 2
done
