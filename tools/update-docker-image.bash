#!/usr/bin/env bash
set -ex

if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: A full version string must be passed in"
  exit 1
fi

version=$1
version_short=$(echo $1 | awk -F "." '{print $1 "." $2 "." $3}')
tools_dir=$(cd "$(dirname "$0")" && pwd)

# DOWNLOAD_URL is the archive of the download site: ${DOWNLOAD_URL}/<version>/<file>, the place the Dockerfile downloads from
wget -O /tmp/newrelic-php5-${version}-linux-musl.tar.gz ${DOWNLOAD_URL}/${version}/newrelic-php5-${version}-linux-musl.tar.gz;
wget -O /tmp/newrelic-php5-${version}-linux-musl.tar.gz.asc ${DOWNLOAD_URL}/${version}/newrelic-php5-${version}-linux-musl.tar.gz.asc \
  || { echo "ERROR: the signature of the tarball could not be downloaded"; exit 1; }

# Pin the hash of a tarball only after its signature is verified
"${tools_dir}/verify-tarball.bash" /tmp/newrelic-php5-${version}-linux-musl.tar.gz /tmp/newrelic-php5-${version}-linux-musl.tar.gz.asc

sha=$(sha256sum /tmp/newrelic-php5-${version}-linux-musl.tar.gz | awk '{print $1}')

mkdir $version_short

cp docker-entrypoint-template $version_short/docker-entrypoint.sh
cd $version_short

sed \
   -e s/"ENV[[:space:]]NEWRELIC_VERSION/ENV NEWRELIC_VERSION=${version}"/ \
   -e s/"ENV[[:space:]]NEWRELIC_SHA/ENV NEWRELIC_SHA=${sha}"/ \
    ../Dockerfile-template > Dockerfile

git checkout -b $version_short
git add .
git commit -m "version bump to ${version_short}"
git tag -a v$version_short -m "GHA created tag"
git push origin HEAD
git push origin --tags
