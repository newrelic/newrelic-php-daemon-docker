#------------------------------------------------------------------------------
# Copyright [2019] New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#------------------------------------------------------------------------------


FROM alpine:3.13 AS build

ENV NEWRELIC_VERSION 9.17.0.300
ENV NEWRELIC_NAME newrelic-php5-${NEWRELIC_VERSION}-linux-musl
ENV NEWRELIC_SHA c96d5c8eab9f4d6438a3eb0fd92af1528adbe5108aee733cede40224b8c5449b

RUN set -ex; \
        wget -O /tmp/${NEWRELIC_NAME}.tar.gz https://download.newrelic.com/php_agent/archive/${NEWRELIC_VERSION}/${NEWRELIC_NAME}.tar.gz; \
        cd /tmp/; \
        echo "$NEWRELIC_SHA  $NEWRELIC_NAME.tar.gz" | sha256sum -c; \
        tar -xzf ${NEWRELIC_NAME}.tar.gz; \
        export NR_INSTALL_SILENT=1; \
        ${NEWRELIC_NAME}/newrelic-install install_daemon

FROM alpine:3.13

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
