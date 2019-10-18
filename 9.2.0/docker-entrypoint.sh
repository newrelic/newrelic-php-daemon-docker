#!/bin/sh
set -e

NEWRELIC_CONFIG_PATH="$(echo -e "${NEWRELIC_CONFIG_PATH}" | tr -d '[:space:]')"
configPath="${NEWRELIC_CONFIG_PATH:-/etc/newrelic/newrelic.cfg}"

if [ -f $configPath ]; then
  set -- "$@" --c $configPath
fi

set -- "$@"  --address=$(hostname):31339

exec /usr/bin/newrelic-daemon --watchdog-foreground "$@"
