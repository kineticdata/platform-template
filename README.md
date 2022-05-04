# platform-template
## Overview 
This repository is designed to migrate Kinetic Core and Task beteen enviroments. Migrations will maintain the unique environmental configurations that allow them to maintain their functionality and connections separate form other environments. (ie Dev, Test, and Prod environmnets) Please see Migrated Components below for details on what is included in a migration.

The scripts leverage the Kinetic Ruby SDK as a gem. Docs can be found here https://rubygems.org/gems/kinetic_sdk

## Usage
This repo should be forked and renamed to something like "platform-template-my-implementation".

The scripts in this repository are examples that may or may not meet your specific needs. The scripts should be thourghouly tested and understood before implementing into a final migration process.

The scripts have been tested in Kinops and on premise installations with configuration differences.

The included Scripts are:
- **export.rb: **Exports an entire Space from the specified server.. (including components which may not be migrated in the scripts below)
- **import.rb:** Migrates components to the specified server.
- **import_git_diff.rb:** Migrates only the recently changed components as identified by git to the specified server.

## Requirements

* Ruby is required on the machine running the scripts
* [Bundler](https://bundler.io/) 
* git (optional but recommended) is required if you want to do "diffing" to better help with building migration scripts
* The user configured to run the import should be a member of the "Task Developer" team. Membership of this team is required for importing some task components.

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
If you wish to push the commits to a remote respository the remote URL must be updated.
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

**Export Configuration Files**
Create an export config for your source server (ie:Development) and, if it is a different server, the baseline source server.

**Import Configuration Files**
Create an import Config for your destination servers (ie: Test, Stage, Production)

### 4. Initial Export
1. Export environment determined above using export.rb *(This creates 2 root directories "Core" and "Task" with the contnets of the environement.)
``` 
ruby export.rb -c "config/<YOUR_SOUCE_SERVER_CONFIG_FILE>.yml "
```
2. Commit your changes into a version control system.
```
git add .
```
3. Commit chnages to git
```
git commit -m "Initial commit of my template" 
```
4. If you have updated the remote repsitory in the steps above you may push the commit to it
```
git push 
```

There is now a repository to help track changes and maintian the Kinetic Core and Task environment.

### Promote Changes to a new Environment
There is now an inital export of whatever was determined to be the baseline export. There are a couple of optons on how to promote the changes to another server.

1. Use import.rb
   This script migrates everthing from an export to another environment. Everything will be migrated even if the source and destination are the same.  In the case of a Form it will be updated even if it is the same and the "Updated At" date and time will be modified for all forms.  
   
   This is the sure way to update an environment to get it into sync with another.
   This script may be used at any point in time to migrate the current state contained in the export to another server.
   
2. Use import_git_diff.rb
   This script will import only the newest changes. Only the changes since the last git commit to the repository will be migrated.  This script works best when it is part of a process that is used consistently. Any one off changes made to the destination server outside of this script may get differences out of sync.  The differences are also determined from one export to another and **not** between the export definitions and the destination server.
   
   This is how this script can be used.
   - The source and destination environment must be in sync to start.
   - Changes are made in the source enviroment
   - The ruby script export.rb is ran for the source environment
   - ```git status ``` is ran to see what has changed.
   - ```git add``` is ran to include only the changes that should be included in a migration
   - ```git commit``` is ran to commit the changed files
   - To see what will be migrated ```git diff HEAD^ HEAD``` may be run
   - Run ```ruby import_git_diff -c "config/<YOUR_SOUCE_SERVER_CONFIG_FILE>.yml "``` with the import configuration script for the destination server to migrate only the recent changes from teh destination server.

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
   
#### BUILD (Space)
   - Datastore Forms
      - Datastore Submissions (configurable by datastore slug)
   - Kapps (All Kapps are exported and imported, see "Kapps" below)
   - Models
   - Web APIs
   
#### CONFIGURATION (Space)
   - Plugins
      - Bridges (not exported, configuration is unique to each environment)
      - Handlers
      - Agent Handlers (not exported)
      - Sources (not exported, configuration is unique to each environment)
   - Settings
      - Details (not exported, configuration is unique to each environment)
      - Attributes (not imported, configuration can unique to each environment)
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
   
#### DEFINITIONS (Space)
  - Attributes
    - Space 
    - User
    - User Profile
    - Teams
    - Datastore Form
  - Security
  - Webhooks  

### Kapps
   Each Kapp is exported and imported.
   
#### BUILD (Kapp)
  - Forms
     - Form Submissions (configurable)
  - WebAPIs
   
#### CONFIGURATION (Kapp)
  - Settings 
    - Details
    - Attributes
    - Fields (n/a)
    - Security
   
#### DEFINITIONS  (Kapp)
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
