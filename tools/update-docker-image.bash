#!/usr/bin/env bash
set -ex

if [[ ! "$1" =~ \d+\.\d+\.\d+\.\d\{3,\} ]]; then
  echo "ERROR: A full version string must be passed in"
  exit 1
fi

version=${1}
version_short=${1::-4}

mkdir $version_short

cp docker-entrypoint-template $version_short/docker-entrypoint.sh
cd $version_short

sed s/"NEWRELIC_VERSION/NEWRELIC_VERSION v${version}"/ ../Dockerfile-template > Dockerfile

git checkout -b $version_short
git add .
git commit -m "version bump"
git push origin $version_short
