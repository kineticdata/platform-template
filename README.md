# platform-template

This repository is designed to be used as a template for seeding new environments or building migration scripts. This repo should be forked and renamed to something like "platform-template-my-implementation".

## Installation

Install gems with [Bundler](https://bundler.io/)

```bash
bundle install
```

## Running

Copy the run-example.rb file and name it run.rb. This file is used to run the actual import, export and custom migration scripts....

Run the script by simply calling from Ruby

```bash
ruby run.rb
```

## Developing

The platform templates use [Bundler](https://bundler.io) to manage gem dependencies. Simply add any necessary gems to `Gemfile`.