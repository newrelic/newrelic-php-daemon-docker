# Daemon Docker Image

This is a repository of base images for the New Relic Daemon. The New Relic Daemon is part of the New Relic PHP Agent. The Dockerfile in this repo is meant to make it easy to run the daemon in a separate container from the agent.

## Running the Image
To run this image, use the commands docker build and docker run:
```
docker build -t newrelic-daemon .
docker run --name some-daemon newrelic-daemon
```

## Accessing logs

The daemon logs are available by accessing the docker logs:

```
docker logs some-daemon
```

### Environment Variables

Setting the `NEWRELIC_DAEMON_PORT` environment variable will change the daemon port. This image defaults to port 31339.
```
docker run --name some-daemon -e NEWRELIC_DAEMON_PORT=1234 newrelic-daemon
```

Setting the `NEWRELIC_CONFIG_PATH` will tell the daemon where to find the config
file you've added to the image. The default location is `/etc/newrelic/newrelic.cfg`.
```
docker run --name some-daemon -v newrelic.cfg:/etc/daemon/daemon.cfg -e NEWRELIC_CONFIG_PATH=/etc/daemon/daemon.cfg newrelic-daemon
```

## Using a custom config file

You may want to run the daemon using a custom config. By default, this image
will look for the config file at `/etc/newrelic/newrelic.cfg`. To change the
default location, set the `NEWRELIC_CONFIG_PATH` environment variable to the
desired path. See the environment variable section to see an example of
changing the config file path.
```
docker run --name some-daemon -v newrelic.cfg:/etc/newrelic/newrelic.cfg newrelic-daemon
```
To find out more about the daemon config visit our [docs site](https://docs.newrelic.com/docs/agents/php-agent/configuration/proxy-daemon-newreliccfg-settings).

## Passing in flags
Additional configuration can be passed in as flags. If you' like to
change the log level, use the following command:
```
docker run php-daemon --loglevel debug
```
To find out more about what flags are possible, execute the following command:
```
docker run php-daemon --help
```

More information about how to setup an agent container can be found on the [docs site](https://docs.newrelic.com/docs/agents/php-agent/advanced-installation/install-php-agent-docker).
