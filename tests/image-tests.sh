#!/usr/bin/env bash
set -ex

cleanup()
{
    docker rm -f $1
}

verify_output()
{
  name=$1
  msg=$2

  shift
  shift

  if [ "$@" ]; then
    echo "PASSED: " $msg
    cleanup $name
  else
    echo "FAILED: " $msg
    cleanup $name
    exit 1
  fi
}

run_tests() {
  docker build -t c-daemon .

  name=version-check
  docker run -d --name $name c-daemon
  sleep 10
  verify_output $name "check the version" -n "$(docker logs $name | grep ${1//\/})"

  name=debug-daemon
  docker run -d --name $name c-daemon --loglevel debug
  sleep 10
  verify_output $name "set the loglevel to debug" -n "$(docker logs $name | grep Debug)"

  name=debug-daemon-with-cmd
  docker run -d --name $name c-daemon --loglevel debug
  sleep 10
  verify_output $name "set the loglevel to debug using cmd override" -n "$(docker logs $name | grep Debug)"

  name=no-logs
  docker run -d --name $name c-daemon --logfile /var/log/newrelic/newrelic.log
  sleep 10
  verify_output $name "set the logfile to /var/log/newrelic/newrelic.log" -n "$(docker exec $name sh -c 'exec cat /var/log/newrelic/newrelic.log')"

  name=no-logs-with-cmd
  docker run -d --name $name c-daemon /usr/bin/newrelic-daemon --logfile /var/log/newrelic/newrelic.log
  sleep 10
  verify_output $name "set the logfile to /var/log/newrelic/newrelic.log using cmd override" -n "$(docker exec $name sh -c 'exec cat /var/log/newrelic/newrelic.log')"

  name=cfg-debug
  echo "loglevel=debug" > newrelic.cfg
  docker run -d --name $name -v $PWD/newrelic.cfg:/etc/newrelic/newrelic.cfg c-daemon --c /etc/newrelic/newrelic.cfg
  sleep 10
  verify_output $name "set the loglevel to debug using cfg file" -n "$(docker logs $name | grep Debug)"

}

versions=$(find . -maxdepth 1 -type d -name '[0-9]*' -exec basename {} \;)
for dir in ${versions}; do
  pushd $dir
  run_tests $dir
  popd
done

exit
