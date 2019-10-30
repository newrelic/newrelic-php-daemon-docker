#!/bin/sh
#------------------------------------------------------------------------------
# Copyright [2019] New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#------------------------------------------------------------------------------
set -e

defaultArgs=" --logfile /proc/self/fd/1 --watchdog-foreground --address=$(hostname):31339"

# this if will check if the first argument is a flag
if [ "${1:0:1}" = '-' ]; then
  set -- /usr/bin/newrelic-daemon $defaultArgs "$@"
elif [ "$1" = '/usr/bin/newrelic-daemon' ]; then
  # Remove the first element from the arguments
  shift 1
  set -- /usr/bin/newrelic-daemon $defaultArgs "$@"
fi

exec "$@"
