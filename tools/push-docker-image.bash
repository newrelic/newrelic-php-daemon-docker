#!/usr/bin/env bash

version=$1

cd ${version} || exit 1

docker build -t newrelic/c-daemon:latest -t newrelic/c-daemon:${version} .

docker login --username=newrelicphp --password ${DOCKER_HUB_PASSWORD}

docker push newrelic/c-daemon
