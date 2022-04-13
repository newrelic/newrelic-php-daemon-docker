#------------------------------------------------------------------------------
# Copyright [2019] New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#------------------------------------------------------------------------------


FROM alpine:3.12.12 AS build

ENV NEWRELIC_VERSION 9.12.0.268
ENV NEWRELIC_NAME newrelic-php5-${NEWRELIC_VERSION}-linux-musl
ENV NEWRELIC_SHA 450dadd960fba27d173676f67e220164f1d62997a8d6b304fe1639a008253702 

RUN set -ex; \
        wget -O /tmp/${NEWRELIC_NAME}.tar.gz https://download.newrelic.com/php_agent/archive/${NEWRELIC_VERSION}/${NEWRELIC_NAME}.tar.gz; \
        cd /tmp/; \
        echo "$NEWRELIC_SHA  $NEWRELIC_NAME.tar.gz" | sha256sum -c; \
        tar -xzf ${NEWRELIC_NAME}.tar.gz; \
        export NR_INSTALL_SILENT=1; \
        ${NEWRELIC_NAME}/newrelic-install install_daemon

FROM alpine:3.12.12

# The daemon needs certs installed to run
RUN apk add --no-cache \
                    ca-certificates

RUN set -ex; \
          mkdir /var/log/newrelic

COPY docker-entrypoint.sh /usr/bin/docker-entrypoint.sh
COPY --from=build /usr/bin/newrelic-daemon /usr/bin/newrelic-daemon

EXPOSE 31339

ENTRYPOINT ["sh","/usr/bin/docker-entrypoint.sh"]

CMD ["/usr/bin/newrelic-daemon"]
