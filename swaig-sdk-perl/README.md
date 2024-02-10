# SWAIG Server Setup Guide

This README outlines the steps necessary to set up a SWAIG (SignalWire AI Agent) server using Dokku, configure it, and test it using the SWAIG CLI tool. 

## Prerequisites

- A server with Dokku installed.
- Git installed on your local machine.
- Access to the domain you intend to use for the SWAIG server.

## Step 1: Obtain an API Key

First, acquire an API key to use with the SWAIG server:

- Visit [API Ninjas](https://api-ninjas.com/) to obtain your API key.

## Step 2: Create the Dokku App

Create a new application on your Dokku server:

```sh
dokku apps:create swaig-server
```

## Step 3: Set Up Git Remote

Add a git remote to your local repository pointing to the Dokku server:

```sh
git remote add dokku dokku@dokku.domain:swaig-server
```

## Step 4: Configure the Application

Set the necessary configuration variables, including your API key and web authentication credentials:

```sh
dokku config:set swaig-server API_KEY=<your_api_key> WEB_AUTH_PASS=<your_password> WEB_AUTH_USER=<your_username>
```

Make sure to replace `<your_api_key>`, `<your_password>`, and `<your_username>` with your actual API key, desired password, and username.

## Step 5: Deploy the Application

Push your application to Dokku:

```sh
git push dokku main
```

## Step 6: Enable SSL

Secure your application with SSL using Let's Encrypt:

```sh
dokku letsencrypt:enable swaig-server
```

## Step 7: Testing with SWAIG CLI

Use the `swaig_cli` tool to test your setup. Here's an example of requesting a function signature:

```sh
./swaig_cli --url https://<WEB_AUTH_USER>:<WEB_AUTH_PASS>@<domain>/swaig --get-signature
```

Replace `<WEB_AUTH_USER>`, `<WEB_AUTH_PASS>`, and `<domain>` with your configured username, password, and domain, respectively.

### Example of calling `get_weather` with `swaig_cli`:

```sh
./swaig_cli --url https://user:pass@swaig-server.signalwire.me/swaig --functions get_weather --arguments '{"city":"Orlando","state":"Florida"}'
```

This command calls the `get_weather` function with the city of Orlando, Florida as the argument.

---

## Conclusion

You have successfully set up a SWAIG server using Dokku, configured it, and tested it using the SWAIG CLI. For further customization and adding more functions to your SWAIG server, refer to the SignalWire AI Agent documentation and the API Ninjas documentation for the APIs you wish to integrate.