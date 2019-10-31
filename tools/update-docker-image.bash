#!/usr/bin/env bash
set -ex

if [[ ! "$1" =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]{3} ]]; then
  echo "ERROR: A full version string must be passed in"
  exit 1
fi

version=$1

IFS='.'
read -ra ADDR <<< "$1"
IFS=' '
version_short="${ADDR[0]}.${ADDR[1]}.${ADDR[2]}"

mkdir $version_short

cp docker-entrypoint-template $version_short/docker-entrypoint.sh
cd $version_short

sed s/"ENV[[:space:]]NEWRELIC_VERSION/ENV NEWRELIC_VERSION v${version}"/ ../Dockerfile-template > Dockerfile

git checkout -b $version_short
git add .
git commit -m "version bump"
git push origin $version_short
