#!/bin/sh
#------------------------------------------------------------------------------
# Copyright [2019] New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#----------------------------------------------------------------------------*/
set -e

NEWRELIC_CONFIG_PATH="$(echo -e "${NEWRELIC_CONFIG_PATH}" | tr -d '[:space:]')"
configPath="${NEWRELIC_CONFIG_PATH:-/etc/newrelic/newrelic.cfg}"

if [ -f $configPath ]; then
  set -- "$@" --c $configPath
fi

exec /usr/bin/newrelic-daemon --logfile /proc/self/fd/1 --watchdog-foreground --address=$(hostname):31339 "$@"
