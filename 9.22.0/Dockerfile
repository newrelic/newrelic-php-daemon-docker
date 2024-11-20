#------------------------------------------------------------------------------
# Copyright [2019] New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#------------------------------------------------------------------------------


FROM alpine:3.13 AS build

ENV NEWRELIC_VERSION 11.3.0.16
ENV NEWRELIC_NAME newrelic-php5-${NEWRELIC_VERSION}-linux-musl
ENV NEWRELIC_SHA bebd7cb1137296c78b04816654c02fe330efc937947a00c6d7239f197835c5d1

RUN set -ex; \
        wget -O /tmp/${NEWRELIC_NAME}.tar.gz https://download.newrelic.com/php_agent/archive/${NEWRELIC_VERSION}/${NEWRELIC_NAME}.tar.gz; \
        cd /tmp/; \
        echo "$NEWRELIC_SHA  $NEWRELIC_NAME.tar.gz" | sha256sum -c; \
        tar -xzf ${NEWRELIC_NAME}.tar.gz; \
        export NR_INSTALL_SILENT=1; \
        ${NEWRELIC_NAME}/newrelic-install install_daemon

FROM alpine:3.13

COPY --from=build /usr/bin/newrelic-daemon /bin/newrelic-daemon

EXPOSE 31339

ENTRYPOINT [ "/bin/newrelic-daemon" ]
CMD ["--foreground", "--logfile", "/proc/self/fd/1", "--port", "31339"]
