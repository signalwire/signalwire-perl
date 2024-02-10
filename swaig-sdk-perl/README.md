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

SWAIG Request:
```json
{
   "version" : "2.0",
   "functions" : [],
   "content_disposition" : "function signature request",
   "action" : "get_signature",
   "content_type" : "text/swaig"
}
```
Response:
```json
[
    {	
      "argument" : {
         "properties" : {
            "city" : {
               "type" : "string",
               "description" : "City name."
            },
            "state" : {
               "type" : "string",
               "description" : "US state for United States cities only. Optional"
            }
         },
         "type" : "object",
         "required" : [
            "city"
         ]
      },
      "purpose" : "latest weather information for any city",
      "web_hook_auth_password" : "pass",
      "function" : "get_weather",
      "web_hook_auth_user" : "user",
      "web_hook_url" : "https://swaig-server.<domain>/swaig"
   },
   {
      "web_hook_auth_user" : "user",
      "web_hook_url" : "https://swaig-server.<domain>/swaig",
      "function" : "get_joke",
      "purpose" : "get a joke to tell the user",
      "web_hook_auth_password" : "pass",
      "argument" : {
         "type" : "object",
         "requried" : [
            "type"
         ],
         "properties" : {
            "type" : {
               "type" : "string",
               "description" : "must either be 'jokes' or 'dadjokes'"
            }
         }
      }
   },
   {
      "purpose" : "get a trivia question",
      "argument" : {
         "properties" : {
            "category" : {
               "type" : "string",
               "description" : "Valid options are artliterature, language, sciencenature, general, fooddrink, peopleplaces, geography, historyholidays, entertainment, toysgames, music, mathematics, religionmythology, sportsleisure. Pick a category at random if not asked for a specific category."
            }
         },
         "required" : [
            "category"
         ],
         "type" : "object"
      },
      "web_hook_url" : "https://swaig-server.<domain>/swaig",
      "web_hook_auth_user" : "user",
      "function" : "get_trivia",
      "web_hook_auth_password" : "pass"
   }
]
```

### Example of calling `get_weather` with `swaig_cli`:

```sh
./swaig_cli --url https://user:pass@swaig-server.signalwire.me/swaig --functions get_weather --arguments '{"city":"Orlando","state":"Florida"}'
```

This command calls the `get_weather` function with the city of Orlando, Florida as the argument.


SWAIG Request:
```json
{
   "argument_desc" : "dummy description",
   "version" : "2.0",
   "app_name" : "swml app",
   "argument" : {
      "parsed" : [
         {
            "state" : "Florida",
            "city" : "Orlando"
         }
      ],
      "raw" : "{\"city\":\"Orlando\",\"state\":\"Florida\"}",
      "substituted" : ""
   },
   "purpose" : "dummy purpose",
   "function" : "get_weather",
   "content_type" : "Conversation/SWAIG-function"
}
```

Response:
```json
{
   "response" : "The weather in Orlando is 78.8F, High of 82.4F, Low of 75.2F, Feels like 78.8F."
}
```

---

# Integrating SWAIG Server in AI Agent SWML

To incorporate a SWAIG (SignalWire AI Agent) server into your AI Agent SWML configuration, you'll need to add the server details under the [SWAIG](https://developer.signalwire.com/sdks/reference/swml/methods/ai/ai_swaig/) `includes` section of your AI Agent SWML file. This allows your application to call external functions hosted on the SWAIG server. Here's how to do it:

## AI SWML Includes Section

Within your SWML configuration, locate or add an `includes` section. In this section, you will specify the SWAIG server along with the functions you intend to use, as well as authentication details. Below is an example configuration:

```json
{
  "includes": [
    {
      "functions": [
        "get_weather",
        "get_joke"
      ],
      "pass": "<WEB_AUTH_USER>",
      "user": "<WEB_AUTH_PASS>",
      "url": "https://<WEB_AUTH_USER>:<WEB_AUTH_PASS>@<domain>/swaig"
    }
  ]
}
```


## Conclusion

You have successfully set up a SWAIG server using Dokku, configured it, and tested it using the SWAIG CLI. For further customization and adding more functions to your SWAIG server, refer to the SignalWire AI Agent documentation and the API Ninjas documentation for the APIs you wish to integrate.




