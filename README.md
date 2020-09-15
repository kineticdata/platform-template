# platform-template
## Overview 
This repository is designed to migrate Kinetic Core and Task beteen enviroments. Migrations will maintain the unique environmental configurations that allow them to maintain their functionality and connections separate form other environments. (ie Dev, Test, and Prod environmnets)

Leverages the Kinetic Ruby SDK as a gem. Docs can be found here https://rubygems.org/gems/kinetic_sdk

## Usage
This repo should be forked and renamed to something like "platform-template-my-implementation".

The scripts in this repository are examples that may or may not meet your specific needs. The scripts should be thourghouly tested and understood before implementing into a final migration process.

The scripts have been tested in Kinops and on premise installations with configuration differences.

The included Scripts are:
- export.rb: Exports an entire Space from the specified server.. (including components which may not be migrated in the scripts below)
- import.rb: Migrates components to the specified server.
- import_git_diff.rb: Migrates only the recently changed components as identified by git to the specified server.

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

## Setup

### 1. Create the Repositiory

- Clone the respositiory into a local directory
```
git clone https://github.com/kineticdata/platform-template.git
```
- (Optional) Connect the repository to a remote repository 
If you wish to push the commits to a remote respository the "remote" must be updated.
``` 
git remote set-url origin https://hostname/USERNAME/REPOSITORY.git
```

### 2. Determine the Baseline Source
Determine the current baseline source for the your implementaiton. This will be the source for the initial export.

**Options:**
1. If you are already in Production with Kinetic Core, this will typically be your production evironment.

2. If you are still developing the implementation and have not yet released to production, this will be your Dev environment.

### 3. Create Config Files
(See the Configuration Files section below)
Create config files in the "/config" directory for the source and destination servers using the examples below.

**Export Configs**
Create an export config for your source server (ie:Development) and, if it is a different server, the baseline source server.

**Import Config**
Create an import Config for your destination servers (ie: Test, Stage, Production)

### 4. Initial Export
1. Export environment determined above using export.rb *(This creates 2 root directories "Core" and "Task" with the contnets of the environement.)
``` ruby export.rb -c "config/<YOUR_SOUCE_SERVER_CONFIG_FILE>.yaml"
2. Commit your changes into a version control system.
```bash
git add .
git commit -m "Initial commit of my template"
```
(If you have updated the remote repsitory in the steps above you may push the commit to it)
```
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

## Configuration Files
The srcipts use YAML files to define the server connection parameters and the scripts behavior.  A config file should be created for each server and script combination. Example configuration files can be found in the /config folder.

#### Configuration File Location
Configuration files should be stored in the /config directory

##### Suggested Naming Convention
The naming convention of the cofig files can be useful to accurately and quickly identfy thier intended use.
<<SERVER_NAME>_<<Import or Export>>_config.yml

##### Export and Import Config File Parameters
Below is a listing of the config elements in the **Export and Import** scripts and how they are used.  Please reference the examples in the /config directory.

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
Below is a listing of the config elements in the **Export** script and how they are used.  Please reference the examples in the /config directory.
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
Below is a listing of the config elements in the **Import** script and how they are used.  Please reference the examples in the /config directory

options:
  delete: true
  
## Migrated Components
Below is a list of components and what is migrated as part of the export and import process.  Not included in a migration is Space slug and name, Bundle configuration, Agent URL, Task URL, Oauth, Security, Bridges, Sources (some), and individual Handler configuration.

### Space
- Build
  - Datastores
  - Datastore Submissions (configurable by datastore slug)
  - Models
  - Web APIs
- Plugins
  - Bridges (not exported, configuration is unique to each environment)
  - Handlers
  - Agent Handlers (not exported)
  - Sources (not exported, configuration is unique to each environment)
  - Settings
    - Details (not exported, configuration is unique to each environment)
    - Attributes
    - Platform Components (not exported, configuration is unique to each environment)
    - Oauth (not exported, configuration is unique to each environment)
    - Security (not exported)
    - Workflow 
      - Engine (not exported)
      - Categories
      - Policy Rules
      - Licenses (not exported)
  - Teams
  - Translations (not exported)
  - Users (not exported)
- Definitions
  - Attributes
    - Space 
    - User
    - User Profile
    - Teams
    - Datastore Form
  - Security
  - Webhooks  

### Kapps
- Build
  - Forms
  - Form Submissions (configurable)
  - WebAPIs
- Configuration
  - Settings 
    - Details
    - Attributes
    - Fields (n/a)
    - Security
- Definitions 
  - Attributes  
    - Kapp
    - Category
    - Form
  - Categories
  - Form Types
  - Security
  - Webhooks

### Global Workflow
- Trees
- Routines

## Developing

The platform templates use [Bundler](https://bundler.io) to manage gem dependencies. Simply add any other gems you'd like to use in your scripts to the `Gemfile`.
