# Daemon Docker Image

This is a repository of base images for the New Relic Daemon. The New Relic Daemon is part of the New Relic PHP Agent. The Dockerfile in this repo is meant to make it easy to run the daemon in a separate container from the agent.

## Running the Image
To run this image, use the commands docker build and docker run:
```
docker build -t newrelic-daemon .
docker run --name some-daemon newrelic-daemon
```
Setting the `NEWRELIC_DAEMON_PORT` environment variable will change the daemon port. This image defaults to port 31339.
```
docker run --name some-daemon -e NEWRELIC_DAEMON_PORT=1234 newrelic-daemon
```
More information about how to setup an agent container can be found on the [docs site](https://docs.newrelic.com/docs/agents/php-agent/advanced-installation/install-php-agent-docker).
