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

### Build Config Files for dev and prod
explain how to do that here...

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
