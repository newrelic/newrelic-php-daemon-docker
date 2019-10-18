#!/bin/bash
set -eo pipefail

runDaemon="/usr/bin/newrelic-daemon --watchdog-foreground --logfile /proc/self/fd/1"
addressRegex="^\s*address\s*="
NEWRELIC_CONFIG_PATH="$(echo -e "${NEWRELIC_CONFIG_PATH}" | tr -d '[:space:]')"
configPath="${NEWRELIC_CONFIG_PATH:-/etc/newrelic/newrelic.cfg}"

if [ -f $configPath ]; then
  runDaemon="$runDaemon --c $configPath"
  if grep -q "$addressRegex" $configPath && [ -z "${NEWRELIC_DAEMON_PORT}" ]; then
    eval $runDaemon
    exit
  fi
fi

runDaemon="$runDaemon --address=$(hostname):${NEWRELIC_DAEMON_PORT:-31339}"
eval $runDaemon
