#!/bin/bash
set -eo pipefail

runDaemon="/usr/bin/newrelic-daemon --watchdog-foreground --logfile /proc/self/fd/1"
addressRegex="^\s*address\s*="
configPath="${NEWRELIC_CONFIG_PATH:-/etc/newrelic/newrelic.cfg}"

if [ -f $configPath ]; then
  runDaemon="$runDaemon --c $configPath"
  if ! grep -q "$addressRegex" $configPath; then
    runDaemon="$runDaemon --address=$(hostname):${NEWRELIC_DAEMON_PORT:-31339}"
  fi
fi

eval $runDaemon
