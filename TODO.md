## Questions
* why do we have "api" "agent_api" and "proxy_url" in the configuration?
* why not just include the subdomain in the URL.  (Other SDK Examples do not inlcude it)
* Fix issue with windows
* Come up with a better way to create config files that can be used in scripts
  * config-:envName.yaml
  * in scripts, check to see if a config param was passed in and if so, read the file and use its values
* move brian p's migration script into this repo
* improve readme
* build "Migrating Data" community article that links to this repo
* Import_script.rb
* --add import of form type into kapps
* --space.json file will always be different.  How to address this?
* --task categories are not currently migrated. Should they be migrated?
* --should teams be migrated?
* reorganize repo as such
```
/config
    /example.yaml
    *gitignore the rest
/export-data
    /core
    /task
/example-scripts
    /migrate-attribute-defs.rb
    /other-example.rb
    /complicated-migration
        /dependencies.rb
        /helper.rb
        /migration.rb
    /export-users-to-csv.rb
    /clean-gdpr-data.rb
    /export-form-sub
/migration-scripts
    /may-2020-migration.rb
    /example-migration.rb        
import.rb
export.rb
```
