#!/usr/bin/env bash

version=$1

cd ${version} || exit 1

docker build -t newrelic/php-daemon:latest -t newrelic/php-daemon:${version} .

docker login --username=newrelicphp --password ${DOCKER_HUB_PASSWORD}

docker push newrelic/php-daemon
