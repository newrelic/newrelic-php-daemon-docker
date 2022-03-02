#!/usr/bin/env bash

yes | docker system prune -a

version=$1

cd ${version} || exit 1

docker build -t newrelic/php-daemon:latest -t newrelic/php-daemon:${version} .

docker login --username=newrelicphp --password ${DOCKER_HUB_PAT}

docker push newrelic/php-daemon
