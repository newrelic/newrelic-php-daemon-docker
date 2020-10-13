[![Community Project header](https://github.com/newrelic/open-source-office/raw/master/examples/categories/images/Community_Project.png)](https://github.com/newrelic/open-source-office/blob/master/examples/categories/index.md#community-project)

# Daemon Docker Image

[![Build Status](https://travis-ci.org/newrelic/newrelic-php-daemon-docker.svg?branch=master)](https://travis-ci.org/newrelic/newrelic-php-daemon-docker)

This is a repository of base images for the New Relic Daemon. The New Relic Daemon is part of the New Relic PHP Agent. The Dockerfile in this repo is meant to make it easy to run the daemon in a separate container from the agent.

## Build the PHP Agent Daemon
Use the `docker build` command to build this image:
```
docker build -t newrelic-daemon
```

## Getting started
After building, it can be run using `docker run`. Use the `--name` flag to name the `newrelic-daemon` image. 

```
docker run --name some-daemon newrelic-daemon
```

### Accessing logs
The daemon logs are available by using `docker logs`:

```
docker logs some-daemon
```

### Using a custom config file

You may want to run the daemon using a custom config. The `-c` daemon flag must
be set to the location of the config file. The `-v` flag will copy a local
config file into the container. An absolute path is required when using the `-v`
flag.
```
docker run --name some-daemon -v $PWD/newrelic.cfg:/etc/newrelic/newrelic.cfg newrelic-daemon -c /etc/newrelic/newrelic.cfg
```

To find out more about the daemon config visit our [docs](https://docs.newrelic.com/docs/agents/php-agent/configuration/proxy-daemon-newreliccfg-settings).

### Passing in flags
Additional configuration can be passed in as flags. If you' like to
change the log level, use the following command:
```
docker run newrelic-daemon --loglevel debug
```
To find out more about what flags are possible, execute the following command:
```
docker run newrelic-daemon --help
```

More information about how to setup an agent container can be found on the [docs](https://docs.newrelic.com/docs/agents/php-agent/advanced-installation/install-php-agent-docker).

## Support

Should you need assistance with New Relic products, you are in good hands with several support channels.

If the issue has been confirmed as a bug or is a feature request, file a GitHub issue.

**Support Channels**

* [New Relic Documentation](LINK to specific docs page): Comprehensive guidance for using our platform
* [New Relic Community](LINK to specific community page): The best place to engage in troubleshooting questions
* [New Relic Developer](https://developer.newrelic.com/): Resources for building a custom observability applications
* [New Relic University](https://learn.newrelic.com/): A range of online training for New Relic users of every level

## Privacy
At New Relic we take your privacy and the security of your information seriously, and are committed to protecting your information. We must emphasize the importance of not sharing personal data in public forums, and ask all users to scrub logs and diagnostic information for sensitive information, whether personal, proprietary, or otherwise.

We define “Personal Data” as any information relating to an identified or identifiable individual, including, for example, your name, phone number, post code or zip code, Device ID, IP address, and email address.

For more information, review [New Relic’s General Data Privacy Notice](https://newrelic.com/termsandconditions/privacy).

## Contribute

We encourage your contributions to improve our php Daemon docker! Keep in mind that when you submit your pull request, you'll need to sign the CLA via the click-through using CLA-Assistant. You only have to sign the CLA one time per project.

If you have any questions, or to execute our corporate CLA (which is required if your contribution is on behalf of a company), drop us an email at opensource@newrelic.com.

**A note about vulnerabilities**

As noted in our [security policy](../../security/policy), New Relic is committed to the privacy and security of our customers and their data. We believe that providing coordinated disclosure by security researchers and engaging with the security community are important means to achieve our security goals.

If you believe you have found a security vulnerability in this project or any of New Relic's products or websites, we welcome and greatly appreciate you reporting it to New Relic through [HackerOne](https://hackerone.com/newrelic).

If you would like to contribute to this project, review [these guidelines](./CONTRIBUTING.md).

To [all contributors](<LINK TO contributors>), we thank you!  Without your contribution, this project would not be what it is today.  We also host a community project page dedicated to [Project Name](<LINK TO https://opensource.newrelic.com/projects/... PAGE>).

## License
newrelic-php-daemon-docker is licensed under the [Apache 2.0](http://apache.org/licenses/LICENSE-2.0.txt) License.
