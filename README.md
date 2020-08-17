# platform-template
## Overview 
This repository is designed to be used as a template for seeding new environments or building migration scripts. 

Leverages the Kinetic Ruby SDK -- docs can be found here...

## Usage
This repo should be forked and renamed to something like "platform-template-my-implementation".

The scripts in this repository are examples that are meant to be tweaked to your exact needs. Typically customers want to have the following types of scripts:

* export: for exporting an entire environment.
* import: for performing incremental migrations from one environment to another.
* install: for seeding a brand new environment **CAUTION** This will delete an existing space and add a new one.  Submissions and other data will be lost.

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

#### Configuration File 
Yaml configuration files are used for the Export and Import Scripts. Example configuration files can be found in the /config folder.

##### Suggested Naming Convention
The naming convention of the cofig files can be useful to accurately and quickly identfy thier intended use.
<<SERVER_NAME>_<<Import or Export>>_config.yml

##### Export and Import Config File Parameters
core:
  server_url: # https://<SPACE>.kinops.io  OR https://<SERVER_NAME>.com/kinetic/<SPACE_SLUG>
  space_slug: # SPACE_SLUG of the environment
  space_name: # SPACE_NAME of the environment
  service_user_username: # Username of a Space Admin
  service_user_password: # Password the Space Admin

task:
  server_url: # https://<SPACE>.kinops.io/app/components/task   OR https://<SERVER_NAME>.com/kinetic/kinetic-task
  space_slug: # SPACE_SLUG of the environment
  space_name: # SPACE_NAME of the environment
http_options:
  log_level: # `debug`, `info`, `warn`, `error`, or `off`
  log_output: #  `stdout` or `stderr`

##### Export Only Config File Parameters

options:
  SUBMISSIONS_TO_EXPORT: 
  - datastore: # true or false: true for datastore forms false for regular form data exports
    formSlug: # Slug of the datastore or form to have submissions exported

  REMOVE_DATA_PROPERTIES: # The listed properties will be removed the form definition
  - createdAt
  - createdBy
  - updatedAt
  - updatedBy
  - closedAt
  - closedBy
  - submittedAt
  - submittedBy
  - id
  - authStrategy
  - key
  - handle

##### Import Only Config File Parameters
options:
  delete: true

## Setup

### Create the Repositiory

1. Create a local directory
2. Clone the respositiory
```
git clone https://github.com/kineticdata/platform-template.git
```
### Create Config Files
Create config files in the "/config" directory for the source and destination servers using the examples above.

### Create the Baseline Repositiory
Determine the current baseline for the repository.  This will typically be your production evironment.  This will give you a baseline to begin building migrations from. 

1. Export Production using export.rb *(This creates 2 root directories "Core" and "Task"....)
2. Commit your changes into a version control system.
```bash
git add .
git commit -m "Initial commit of my template"
git push
```

### Compare Dev and Prod


### Get an export from the development environment
1. Point export script at the source server
2. Export Environment using export.rb
```
ruby export.rb -c "config/foo-web-server.rb"
```
3. Check for differences (git diff)
4. Add desired changes to the repositiory
5. Commit changes.

### Promote Changes to a new Environment
1. Point import script at the source server
2. Run import script
3. Validate Results


## Developing

The platform templates use [Bundler](https://bundler.io) to manage gem dependencies. Simply add any other gems you'd like to use in your scripts to the `Gemfile`.
