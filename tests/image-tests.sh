#!/usr/bin/env bash
set -ex

cleanup()
{
    docker rm -f $1
}

verify_output()
{
  if [ $1 ]; then
    echo "FAILED: " $3
    cleanup $2
    exit 1
  else
    echo "PASSED: " $3
    cleanup $2
  fi
}

run_tests() {
  docker build -t c-daemon .

  name=version-check
  docker run -d --name $name c-daemon
  verify_output "-n $(docker logs $name | grep ${1//\/})" $name "check the version"

  name=debug-daemon
  docker run -d --name $name c-daemon 
  verify_output "-n $(docker logs $name | grep Debug)" $name "set the loglevel to debug"

  name=debug-daemon-with-cmd
  docker run -d --name $name c-daemon --loglevel debug
  verify_output "-n $(docker logs $name | grep Debug)" $name "set the loglevel to debug using cmd override"

  name=no-logs
  docker run -d --name $name c-daemon --logfile /var/log/newrelic/newrelic.log
  verify_output "-n $(docker exec $name sh -c 'exec cat /var/log/newrelic/newrelic.log')" $name "set the logfile to /var/log/newrelic/newrelic.log"

  name=no-logs-with-cmd
  docker run -d --name $name c-daemon /usr/bin/newrelic-daemon --logfile /var/log/newrelic/newrelic.log
  verify_output "-n $(docker exec $name sh -c 'exec cat /var/log/newrelic/newrelic.log')" $name "set the logfile to /var/log/newrelic/newrelic.log using cmd override"

  name=cfg-debug
  echo "loglevel=debug" > newrelic.cfg
  docker run -d --name $name -v $PWD/newrelic.cfg:/etc/newrelic/newrelic.cfg c-daemon --c /etc/newrelic/newrelic.cfg
  verify_output "-n $(docker logs $name | grep Debug)" $name "set the loglevel to debug using cfg file"

}

versions=(*/)

# directories that don't have a docker image in them
nonDockerDirs=(tests/ docs/)

# remove directories we don't want to test
for target in "${nonDockerDirs[@]}"; do
  for i in "${!versions[@]}"; do
    if [[ ${versions[i]} = "$target" ]]; then
      unset 'versions[i]'
    fi
  done
done
echo "${versions[@]}"

for dir in "${versions[@]}"; do
  cd $dir
  run_tests $dir
done

exit
