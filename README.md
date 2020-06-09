# platform-template
## Overview 
This repository is designed to be used as a template for seeding new environments or building migration scripts. 

Leverages the Kinetic Ruby SDK -- docs can be found here...

## Usage
This repo should be forked and renamed to something like "platform-template-my-implementation".

The scripts in this repository are examples that are meant to be tweaked to your exact needs. Typically customers want to have the following types of scripts:

* export: for exporting an entire environment
* import: for seeding a brand new environment
* migrate: custom scripts for performing incremental migrations from one environment to another.

## Requirements

* ruby is required on the machine running the scripts
* [Bundler](https://bundler.io/) 
* git (optional but recommended) is required if you want to do "diffing" to better help with building migration scripts

## Getting Started

### Install the ruby gems 
Install gems with [Bundler](https://bundler.io/)

```bash
bundle install
```

### Build Configuration Files for dev and prod
explain how to do that here...
#### Configuration File Location
Configuration files should be store in in the /config directory

#### Configuration File Parameters
```{
  "core" : { 
    "api" : # {Export and Import; Required} Defines the Server API URL
    "agent_api" : # {Export and Import; Required} Defines the Agent API URL
    "proxy_url" : # {Export and Import; Required} Defines the Proxy API URL
    "server" : "# {Export and Import; Required} Defines the Server API URL
    "space_slug" : # {Export and Import; Required} Defines Space Slug
    "space_name" : # {Export and Import; Required} Defines the Space Name
    "service_user_username" : # {Export and Import; Required} Defines the Username for Authentication
    "service_user_password" : # {Export and Import; Required} Defines the Password for Authentication
    "task_api_v2" : # {Export and Import; Required} Defines the Task Server API URL
  },
  "options" : {
      "delete" : # {Import; Required} Defines if configurations in the import but absent on the destination server should be deleted from the destination sever.
    },
  "http_options" : {
    "log_level" : # {Import; Required} Defines the log Level. Values are "stdout", "stderr"
    "log_output" : # {Import; Required} Defines log output location.  Values are "error", "warn","info","debug"
  }
}
```

#### Suggested Naming Convention
The naming convention of the cofig files can be useful to accurately and quickly identfy thier intended use.
<<SERVER_NAME>_<<Import or Export>>_config.txt

#### Export Config Example
```{
  "core" : {
    "api" : "https://<<YOUR KINOPS SPACE>>.kinops.io/app/api/v1",
    "agent_api" : "https://<<YOUR KINOPS SPACE>>.kinops.io/app/components/agent/app/api/v1",
    "proxy_url" : "https://<<YOUR KINOPS SPACE>>.kinops.io/app/components",
    "server" : "https://<<YOUR KINOPS SPACE>>.kinops.io/",
    "space_slug" : "<<<SPACE NAME>>",
    "space_name" : "SPACE SLUG",
    "service_user_username" : "<<USER NAME>>",
    "service_user_password" : "<<PASSWORD>>",
    "task_api_v2" : "https://<<YOUR KINOPS SPACE>>.kinops.io/app/components/task/app/api/v2"
  },
  "http_options" : {
    "log_level" : "info",
    "log_output" : "stderr"
  }
}
```

#### Import Config Example
```{
  "core" : {
    "api" : "https://<<YOUR KINOPS SPACE>>.kinops.io/app/api/v1",
    "agent_api" : "https://<<YOUR KINOPS SPACE>>.kinops.io/app/components/agent/app/api/v1",
    "proxy_url" : "https://<<YOUR KINOPS SPACE>>.kinops.io/app/components",
    "server" : "https://<<YOUR KINOPS SPACE>>.kinops.io/",
    "space_slug" : "<<<SPACE NAME>>",
    "space_name" : "SPACE SLUG",
    "service_user_username" : "<<USER NAME>>",
    "service_user_password" : "<<PASSWORD>>",
    "task_api_v2" : "https://<<YOUR KINOPS SPACE>>.kinops.io/app/components/task/app/api/v2"
  },
  "options" : {
      "delete" : false,
    },
  "http_options" : {
    "log_level" : "info",
    "log_output" : "stderr"
  }
}
```

### Compare Dev and Prod

This will give you a baseline to begin building migrations from. (typically you'll want to export your current production environment).

Get an inital Baseline for the respositiory using data from the production environmnent
1. Export Production using export.rb *(This creates 2 root directories "Core" and "Task"....)
2. Commit your changes into a version control system.
```bash
git add .
git commit -m "Initial commit of my template"
```

### Get an export from the development environment
1. Point export script at the source server
2. Export Environment using export.rb
3. Check for differences (git diff)
4. Add desired changes to the repositiory
5. Commit changes.

### Promote Changes to a new Environment
1. Point import script at the source server
2. Run import script
3. Validate Results


## Developing

The platform templates use [Bundler](https://bundler.io) to manage gem dependencies. Simply add any other gems you'd like to use in your scripts to the `Gemfile`.
