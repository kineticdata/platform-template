# NOTES
# This is a migration tool not an installation tool.  There are certain expectations that the destination is configured and working.
# Agent Server(s) must be added ahead of migration.  /space/settings/platformComponents/agents
# Task Server must be added ahead of migration.  /space/settings/platformComponents/task
# Task Sources must be manually maintained
# Bridges must be added ahead of migration.  /space/plugins/bridges
# Agent Handlers are not migrated by design.  They intentionally must be manually added.
# Teams are not deleted from destination.  It could be too dangerous to delete them.

# TODO

# RUNNING THE SCRIPT:
#   ruby import_script.rb -c "<<Dir/CONFIG_FILE.rb>>"
#   ruby import_script -c "config/foo-web-server.rb"
#
# Example Config File Values (See Readme for additional details)
#
=begin yml config file example
  ---
  core:
    # server_url: https://<SPACE>.kinops.io  OR https://<SERVER_NAME>.com/kinetic/<SPACE_SLUG>
    server_url: https://web-server.com
    space_slug: <SPACE_SLUG>
    space_name: <SPACE_NAME>
    service_user_username: <USER_NAME>
    service_user_password: <PASSWORD>
  options:
    delete: true
  task:
    # server_url: https://<SPACE>.kinops.io/app/components/task   OR https://<SERVER_NAME>.com/kinetic-task
    server_url: https://web-server.com
    service_user_username: <USER_NAME>
    service_user_password: <PASSWORD>
  http_options:
    log_level: info
    log_output: stderr
=end

require 'logger'
require 'json'
require 'rexml/document'
require 'optparse'
require 'kinetic_sdk'
include REXML

template_name = "platform-template"

logger = Logger.new(STDERR)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  date_format = datetime.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
  "[#{date_format}] #{severity}: #{msg}\n"
end

#########################################

# Determine the Present Working Directory
pwd = File.expand_path(File.dirname(__FILE__))

ARGV << '-h' if ARGV.empty?

# The options specified on the command line will be collected in *options*.
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"

  opts.on("-c", "--c CONFIG_FILE", "The Configuration file to use") do |config|
    options["CONFIG_FILE"] = config
  end
  
  # No argument, shows at tail.  This will print an options summary.
  # Try it and see!
  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

#Now raise an exception if we have not found a CONFIG_FILE option
raise OptionParser::MissingArgument if options["CONFIG_FILE"].nil?


# determine the directory paths
platform_template_path = File.dirname(File.expand_path(__FILE__))
core_path = File.join(platform_template_path, "core")
task_path = File.join(platform_template_path, "task")

# ------------------------------------------------------------------------------
# methods
# ------------------------------------------------------------------------------



# ------------------------------------------------------------------------------
# constants
# ------------------------------------------------------------------------------



# ------------------------------------------------------------------------------
# setup
# ------------------------------------------------------------------------------

logger.info "Installing gems for the \"#{template_name}\" template."
Dir.chdir(platform_template_path) { system("bundle", "install") }



# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------
vars = {}
# Read the config file specified in the command line into the variable "vars"
if File.file?(file = "#{platform_template_path}/#{options['CONFIG_FILE']}")
  vars.merge!( YAML.load(File.read("#{platform_template_path}/#{options['CONFIG_FILE']}")) )
elsif
  raise "Config file not found: #{file}"
end

# Set http_options based on values provided in the config file.
http_options = (vars["http_options"] || {}).each_with_object({}) do |(k,v),result|
  result[k.to_sym] = v
end

# Set option values to default values if not included
vars["options"] = !vars["options"].nil? ? vars["options"] : {}
vars["options"]["delete"] = !vars["options"]["delete"].nil? ? vars["options"]["delete"] : false

logger.info "Importing using the config: #{JSON.pretty_generate(vars)}"


space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server_url"],
  space_slug: vars["core"]["space_slug"],
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{core_path}" })
})

puts "Are you sure you want to perform an import of data to #{vars["core"]["server_url"]}? [Y/N]"
STDOUT.flush
case (gets.downcase.chomp)
when 'y'
  puts "Continuing Import"
  STDOUT.flush
else
  abort "Exiting Import"
end

###################################################################
# ------------------------------------------------------------------------------
# Update Space Attributes
# ------------------------------------------------------------------------------

sourceSpaceAttributeArray = []
destinationSpaceAttributeArray = (space_sdk.find_space_attribute_definitions().content['spaceAttributeDefinitions']|| {}).map { |definition|  definition['name']}

if File.file?(file = "#{core_path}/space/spaceAttributeDefinitions.json")
  spaceAttributeDefinitions = JSON.parse(File.read(file))

  spaceAttributeDefinitions.each { |attribute|
      if destinationSpaceAttributeArray.include?(attribute['name'])
        space_sdk.update_space_attribute_definition(attribute['name'], attribute)
      else
        space_sdk.add_space_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
      end
      sourceSpaceAttributeArray.push(attribute['name'])
  }  
end   

destinationSpaceAttributeArray.each { | attribute |
  if vars["options"]["delete"] && !sourceSpaceAttributeArray.include?(attribute)
      space_sdk.delete_space_attribute_definition(attribute)
  end
}

# ------------------------------------------------------------------------------
# Update User Attributes
# ------------------------------------------------------------------------------
sourceUserAttributeArray = []
destinationUserAttributeArray = (space_sdk.find_user_attribute_definitions().content['userAttributeDefinitions'] || {}).map { |definition|  definition['name']}

if File.file?(file = "#{core_path}/space/userAttributeDefinitions.json")
  userAttributeDefinitions = JSON.parse(File.read(file))
  userAttributeDefinitions.each { |attribute|
      if destinationUserAttributeArray.include?(attribute['name'])
        space_sdk.update_user_attribute_definition(attribute['name'], attribute)
      else
        space_sdk.add_user_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
      end
      sourceUserAttributeArray.push(attribute['name'])
  }  
end

destinationUserAttributeArray.each { | attribute |
  if vars["options"]["delete"] && !sourceUserAttributeArray.include?(attribute)
      space_sdk.delete_user_attribute_definition(attribute)
  end
}
# ------------------------------------------------------------------------------
# Update User Profile Attributes
# ------------------------------------------------------------------------------

sourceUserProfileAttributeArray = []
destinationUserProfileAttributeArray = (space_sdk.find_user_profile_attribute_definitions().content['userProfileAttributeDefinitions'] || {}).map { |definition|  definition['name']}

if File.file?(file = "#{core_path}/space/userProfileAttributeDefinitions.json")
  userProfileAttributeDefinitions = JSON.parse(File.read(file))

  userProfileAttributeDefinitions.each { |attribute|
      if destinationUserProfileAttributeArray.include?(attribute['name'])
        space_sdk.update_user_profile_attribute_definition(attribute['name'], attribute)
      else
        space_sdk.add_user_profile_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
      end
      sourceUserProfileAttributeArray.push(attribute['name'])
  }  
end  

destinationUserProfileAttributeArray.each { | attribute |
  if vars["options"]["delete"] && !sourceUserProfileAttributeArray.include?(attribute)
      space_sdk.delete_user_profile_attribute_definition(attribute)
  end
}


# ------------------------------------------------------------------------------
# Update Team Attributes
# ------------------------------------------------------------------------------

sourceTeamAttributeArray = []
destinationTeamAttributeArray = (space_sdk.find_team_attribute_definitions().content['teamAttributeDefinitions']|| {}).map { |definition|  definition['name']}

if File.file?(file = "#{core_path}/space/teamAttributeDefinitions.json")
  teamAttributeDefinitions = JSON.parse(File.read(file))
  teamAttributeDefinitions.each { |attribute|
      if destinationTeamAttributeArray.include?(attribute['name'])
        space_sdk.update_team_attribute_definition(attribute['name'], attribute)
      else
        space_sdk.add_team_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
      end
      sourceTeamAttributeArray.push(attribute['name'])
  }  
end

destinationTeamAttributeArray.each { | attribute |
  if vars["options"]["delete"] && !sourceTeamAttributeArray.include?(attribute)
      space_sdk.delete_team_attribute_definition(attribute)
  end
}


# ------------------------------------------------------------------------------
# Update Datastore Attributes
# ------------------------------------------------------------------------------

sourceDatastoreAttributeArray = []
destinationDatastoreAttributeArray =(space_sdk.find_datastore_form_attribute_definitions().content['datastoreFormAttributeDefinitions'] || {}).map { |definition|  definition['name']}

if File.file?(file = "#{core_path}/space/datastoreFormAttributeDefinitions.json")
  datastoreFormAttributeDefinitions = JSON.parse(File.read(file))
  datastoreFormAttributeDefinitions.each { |attribute|
      if destinationDatastoreAttributeArray.include?(attribute['name'])
        space_sdk.update_datastore_form_attribute_definition(attribute['name'], attribute)
      else
        space_sdk.add_datastore_form_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
      end
      sourceDatastoreAttributeArray.push(attribute['name'])
  }  
end

destinationDatastoreAttributeArray.each { | attribute |
  if vars["options"]["delete"] && !sourceDatastoreAttributeArray.include?(attribute)
      #Delete form is disabled
      #space_sdk.delete_datastore_form_attribute_definition(attribute)
  end
}


# ------------------------------------------------------------------------------
# Update Security Policy
# ------------------------------------------------------------------------------

sourceSecurityPolicyArray = []
destinationSecurityPolicyArray = (space_sdk.find_space_security_policy_definitions().content['securityPolicyDefinitions'] || {}).map { |definition|  definition['name']}

if File.file?(file = "#{core_path}/space/securityPolicyDefinitions.json")
  securityPolicyDefinitions = JSON.parse(File.read(file))
  securityPolicyDefinitions.each { |attribute|
      if destinationSecurityPolicyArray.include?(attribute['name'])
        space_sdk.update_space_security_policy_definition(attribute['name'], attribute)
      else
        space_sdk.add_space_security_policy_definition(attribute)
      end
      sourceSecurityPolicyArray.push(attribute['name'])
  }  
end

destinationSecurityPolicyArray.each { | attribute |
  if vars["options"]["delete"] && !sourceSecurityPolicyArray.include?(attribute)
      space_sdk.delete_space_security_policy_definition(attribute)
  end
}


# ------------------------------------------------------------------------------
# import bridge models
# *NOTE* - This if the bridge doesn't exist the model will be imported w/ an empty "Bridge Slug" value.
# ------------------------------------------------------------------------------

destinationModels = space_sdk.find_bridge_models()
destinationModels_Array = (destinationModels.content['models'] || {}).map{ |model| model['activeMappingName']}

Dir["#{core_path}/space/models/*.json"].each{ |model|
  body = JSON.parse(File.read(model))
  if destinationModels_Array.include?(body['name'])
    space_sdk.update_bridge_model(body['name'], body)
  elsif
    space_sdk.add_bridge_model(body)
  end
}

# ------------------------------------------------------------------------------
# delete bridge models
# Delete any Bridges from the destination which are missing from the import data
# ------------------------------------------------------------------------------
SourceModelsArray = Dir["#{core_path}/space/models/*.json"].map{ |model| JSON.parse(File.read(model))['name'] }

destinationModels_Array.each do |model|
  if vars["options"]["delete"] && !SourceModelsArray.include?(model)
    space_sdk.delete_bridge_model(model)
  end
end

# ------------------------------------------------------------------------------
# Import Space Web APIs
# ------------------------------------------------------------------------------

sourceSpaceWebApisArray = []
destinationSpaceWebApisArray = (space_sdk.find_space_webapis().content['webApis'] || {}).map { |definition|  definition['slug']}

  
Dir["#{core_path}/space/webApis/*"].each{ |file|
  body = JSON.parse(File.read(file))
  if destinationSpaceWebApisArray.include?(body['slug'])
    space_sdk.update_space_webapi(body['slug'], body)
  else
    space_sdk.add_space_webapi(body)
  end
  sourceSpaceWebApisArray.push(body['slug'])
} 

# ------------------------------------------------------------------------------
# Delete Space Web APIs
# Delete any Web APIs from the destination which are missing from the import data
# ------------------------------------------------------------------------------
destinationSpaceWebApisArray.each { | webApi |
  if vars["options"]["delete"] && !sourceSpaceWebApisArray.include?(webApi)
      space_sdk.delete_space_webapi(webApi)
  end
}

# ------------------------------------------------------------------------------
# import datastore forms
# ------------------------------------------------------------------------------
destinationDatastoreForms = [] #From destination server
sourceDatastoreForms = [] #From import data

logger.info "Importing datastore forms for #{vars["core"]["space_slug"]}"

  destinationDatastoreForms = (space_sdk.find_datastore_forms().content['forms'] || {}).map{ |datastore| datastore['slug']}
  Dir["#{core_path}/space/datastore/forms/*.json"].each { |datastore|
    body = JSON.parse(File.read(datastore))
    sourceDatastoreForms.push(body['slug'])
    if destinationDatastoreForms.include?(body['slug'])
      space_sdk.update_datastore_form(body['slug'], body)
    else
      space_sdk.add_datastore_form(body)
    end
  }

# ------------------------------------------------------------------------------
# delete datastore forms
# Delete any form from the destination which are missing from the import data
# ------------------------------------------------------------------------------


destinationDatastoreForms.each { |datastore_slug|
  if vars["options"]["delete"] && !sourceDatastoreForms.include?(datastore_slug)
    space_sdk.delete_datastore_form(datastore_slug)
  end
}

# ------------------------------------------------------------------------------
# Import Datastore Data
# ------------------------------------------------------------------------------
Dir["#{core_path}/space/datastore/forms/**/submissions*.ndjson"].sort.each { |filename|
  dir = File.dirname(filename)
  form_slug = filename.match(/forms\/(.+)\/submissions\.ndjson/)[1]
  (space_sdk.find_all_form_datastore_submissions(form_slug).content['submissions'] || []).each { |submission|
    space_sdk.delete_datastore_submission(submission['id'])
  }
  File.readlines(filename).each { |line|
    submission = JSON.parse(line) 
    submission["values"].map { |field, value|
        # if the value contains an array of files
        if value.is_a?(Array) && !value.empty? && value.first.is_a?(Hash) && value.first.has_key?('path')
          value.map.with_index { |file, index|
            # add 'path' key to the attribute value indicating the location of the attachment          
            file['path'] = "#{dir}#{file['path']}"
          }
        end
    }
    body = { 
      "values" => submission["values"],
      "coreState" => submission["coreState"]
    }
    space_sdk.add_datastore_submission(form_slug, body).content
  }
}

# ------------------------------------------------------------------------------
# import space teams
# ------------------------------------------------------------------------------
if (teams = Dir["#{core_path}/space/teams/*.json"]).length > 0 
  SourceTeamArray = []
  destinationTeamsArray = (space_sdk.find_teams().content['teams'] || {}).map{ |team| {"slug" => team['slug'], "name"=>team['name']} }
  teams.each{ |team|
    body = JSON.parse(File.read(team))
    if !destinationTeamsArray.find {|destination_team| destination_team['slug'] == body['slug']  }.nil?
      space_sdk.update_team(body['slug'], body)
    else
      space_sdk.add_team(body)
    end
    #Add Attributes to the Team
    (body['attributes'] || []).each{ | attribute |
     space_sdk.add_team_attribute(body['name'], attribute['name'], attribute['values'])
    }
    SourceTeamArray.push({'name' => body['name'], 'slug'=>body['slug']} )
  }

  # ------------------------------------------------------------------------------
  # delete space teams
  # TODO: A method doesn't exist for deleting the team
  # ------------------------------------------------------------------------------

  destinationTeamsArray.each { |team|
    #if !SourceTeamArray.include?(team)
    if SourceTeamArray.find {|source_team| source_team['slug'] == team['slug']  }.nil?
      #Delete has been disabled.  It is potentially too dangerous to include w/o advanced knowledge.
      #space_sdk.delete_team(team['slug'])
    end
  }
end

# ------------------------------------------------------------------------------
# import kapp data
# ------------------------------------------------------------------------------

kapps_array = []
Dir["#{core_path}/space/kapps/*"].each { |file|   
  kapp_slug = file.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}.last.gsub('.json','')
  next if kapps_array.include?(kapp_slug) # If the loop has already iterated over the kapp from the kapp file or the kapp dir skip the iteration
  kapps_array.push(kapp_slug) # Append the kapp_slug to an array so a duplicate iteration doesn't occur
  kapp = {}
  kapp['slug'] = kapp_slug # set kapp_slug
    
  if File.file?(file) or ( File.directory?(file) and File.file?(file = "#{file}.json") ) # If the file is a file or a dir with a corresponding json file
    kapp = JSON.parse( File.read(file) )
    kappExists = space_sdk.find_kapp(kapp['slug']).code.to_i == 200  
    if kappExists
      space_sdk.update_kapp(kapp['slug'], kapp)
    else
      space_sdk.add_kapp(kapp['name'], kapp['slug'], kapp)
    end
  end 

  # ------------------------------------------------------------------------------
  # Migrate Kapp Attribute Definitions
  # ------------------------------------------------------------------------------
  if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/kappAttributeDefinitions.json")
    sourceKappAttributeArray = []
    destinationKappAttributeArray = (space_sdk.find_kapp_attribute_definitions(kapp['slug']).content['kappAttributeDefinitions'] || {}).map { |definition|  definition['name']}
    kappAttributeDefinitions = JSON.parse(File.read(file))
    (kappAttributeDefinitions || []).each { |attribute|
        if destinationKappAttributeArray.include?(attribute['name'])
          space_sdk.update_kapp_attribute_definition(kapp['slug'], attribute['name'], attribute)
        else
          space_sdk.add_kapp_attribute_definition(kapp['slug'], attribute['name'], attribute['description'], attribute['allowsMultiple'])
        end
        sourceKappAttributeArray.push(attribute['name'])
    }   
    # ------------------------------------------------------------------------------
    # Delete Kapp Attribute Definitions
    # ------------------------------------------------------------------------------
    destinationKappAttributeArray.each { | attribute |
      if vars["options"]["delete"] && !sourceKappAttributeArray.include?(attribute)
          space_sdk.delete_kapp_attribute_definition(kapp['slug'],attribute)
      end
    }
  end

  # ------------------------------------------------------------------------------
  # Migrate Kapp Category Definitions
  # ------------------------------------------------------------------------------
  if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/categoryAttributeDefinitions.json")
    sourceKappCategoryArray = []
    destinationKappAttributeArray = (space_sdk.find_category_attribute_definitions(kapp['slug']).content['categoryAttributeDefinitions'] || {}).map { |definition|  definition['name']}  
    kappCategoryDefinitions = JSON.parse(File.read(file))
    (kappCategoryDefinitions || []).each { |attribute|
        if destinationKappAttributeArray.include?(attribute['name'])
          space_sdk.update_category_attribute_definition(kapp['slug'], attribute['name'], attribute)
        else
          space_sdk.add_category_attribute_definition(kapp['slug'], attribute['name'], attribute['description'], attribute['allowsMultiple'])
        end
        sourceKappCategoryArray.push(attribute['name'])
    }   
    # ------------------------------------------------------------------------------
    # Delete Kapp Category Definitions
    # ------------------------------------------------------------------------------
    destinationKappAttributeArray.each { | attribute |
      if !sourceKappCategoryArray.include?(attribute)
          space_sdk.delete_category_attribute_definition(kapp['slug'],attribute)
      end
    }
  end
  
  # ------------------------------------------------------------------------------
  # Migrate Kapp Form Attribute Definitions
  # ------------------------------------------------------------------------------
  if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/formAttributeDefinitions.json")
    sourceFormAttributeArray = []
    destinationFormAttributeArray = (space_sdk.find_form_attribute_definitions(kapp['slug']).content['formAttributeDefinitions'] || {}).map { |definition|  definition['name']}
    formAttributeDefinitions = JSON.parse(File.read(file))
    (formAttributeDefinitions || []).each { |attribute|
        if destinationFormAttributeArray.include?(attribute['name'])
          space_sdk.update_form_attribute_definition(kapp['slug'], attribute['name'], attribute)
        else
          space_sdk.add_form_attribute_definition(kapp['slug'], attribute['name'], attribute['description'], attribute['allowsMultiple'])
        end
        sourceFormAttributeArray.push(attribute['name'])
    }   
    # ------------------------------------------------------------------------------
    # Delete Kapp Form Attribute Definitions
    # ------------------------------------------------------------------------------
    destinationFormAttributeArray.each { | attribute |
      if vars["options"]["delete"] && !sourceFormAttributeArray.include?(attribute)
          space_sdk.delete_form_attribute_definition(kapp['slug'],attribute)
      end
    }
  end
  
  # ------------------------------------------------------------------------------
  # Migrate Kapp Form Type Definitions
  # ------------------------------------------------------------------------------
  if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/formTypes.json")
    sourceFormTypesArray = []
    destinationFormTypesArray = (space_sdk.find_formtypes(kapp['slug']).content['formTypes'] || {}).map { |formTypes|  formTypes['name']}
    formTypes = JSON.parse(File.read(file))
    (formTypes || []).each { |body|
      if destinationFormTypesArray.include?(body['name'])
        space_sdk.update_formtype(kapp['slug'], body['name'], body)
      else
        space_sdk.add_formtype(kapp['slug'], body)
      end
      sourceFormTypesArray.push(body['name'])
    }   
    # ------------------------------------------------------------------------------
    # Delete Kapp Form Type Definitions
    # ------------------------------------------------------------------------------
    destinationFormTypesArray.each { | name |
      if vars["options"]["delete"] && !sourceFormTypesArray.include?(name)
          space_sdk.delete_formtype(kapp['slug'],name)
      end
    }
  end

  # ------------------------------------------------------------------------------
  # Migrate Kapp Security Policy Definitions
  # ------------------------------------------------------------------------------
  if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/securityPolicyDefinitions.json")
    sourceSecurtyPolicyArray = []
    destinationSecurtyPolicyArray = (space_sdk.find_security_policy_definitions(kapp['slug']).content['securityPolicyDefinitions'] || {}).map { |definition|  definition['name']}
    securityPolicyDefinitions = JSON.parse(File.read(file))
    (securityPolicyDefinitions || []).each { |attribute|
        if destinationSecurtyPolicyArray.include?(attribute['name'])
          space_sdk.update_security_policy_definition(kapp['slug'], attribute['name'], attribute)
        else
          space_sdk.add_security_policy_definition(kapp['slug'], attribute)
        end
        sourceSecurtyPolicyArray.push(attribute['name'])
    }   

    destinationSecurtyPolicyArray.each { | attribute |
      if vars["options"]["delete"] && !sourceSecurtyPolicyArray.include?(attribute)
          space_sdk.delete_security_policy_definition(kapp['slug'],attribute)
      end
    }
  end
  
  # ------------------------------------------------------------------------------
  # Migrate Kapp Categories
  # ------------------------------------------------------------------------------
  if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/categories.json")
    sourceCategoryArray = []
    destinationCategoryArray = (space_sdk.find_categories(kapp['slug']).content['categories'] || {}).map { |definition|  definition['slug']}
    categories = JSON.parse(File.read(file))
    (categories || []).each { |attribute|
      if destinationCategoryArray.include?(attribute['slug'])
        space_sdk.update_category_on_kapp(kapp['slug'], attribute['slug'], attribute)
      else
        space_sdk.add_category_on_kapp(kapp['slug'], attribute)
      end
      sourceCategoryArray.push(attribute['slug'])
    }
    # ------------------------------------------------------------------------------
    # Delete Kapp Categories
    # ------------------------------------------------------------------------------
     
    destinationCategoryArray.each { | attribute |
      if !sourceCategoryArray.include?(attribute)
          space_sdk.delete_category_on_kapp(kapp['slug'],attribute)
      end
    }
  end

  # ------------------------------------------------------------------------------
  # import space webhooks
  # ------------------------------------------------------------------------------
  sourceSpaceWebhooksArray = []
  destinationSpaceWebhooksArray = (space_sdk.find_webhooks_on_space().content['webhooks'] || {}).map{ |webhook| webhook['name']}

  Dir["#{core_path}/space/webhooks/*.json"].each{ |file|
    webhook = JSON.parse(File.read(file))
    if destinationSpaceWebhooksArray.include?(webhook['name'])
       space_sdk.update_webhook_on_space(webhook['name'], webhook)
    elsif
      space_sdk.add_webhook_on_space(webhook)
    end
    sourceSpaceWebhooksArray.push(webhook['name'])
  }

  # ------------------------------------------------------------------------------
  # delete space webhooks
  # TODO: A method doesn't exist for deleting the webhook
  # ------------------------------------------------------------------------------

  destinationSpaceWebhooksArray.each do |webhook|
    if vars["options"]["delete"] && !sourceSpaceWebhooksArray.include?(webhook)
      space_sdk.delete_webhook_on_space(webhook)
    end
  end    

  # ------------------------------------------------------------------------------
  # Migrate Kapp Webhooks
  # ------------------------------------------------------------------------------
  sourceWebhookArray = []
  webhooks_on_kapp = space_sdk.find_webhooks_on_kapp(kapp['slug']) 
  
  if webhooks_on_kapp.code=="200" 
    destinationWebhookArray = (webhooks_on_kapp.content['webhooks'] || {}).map { |definition|  definition['name']}
    Dir["#{core_path}/space/kapps/#{kapp['slug']}/webhooks/*.json"].each{ |webhookFile|
        webhookDef = JSON.parse(File.read(webhookFile))
        if destinationWebhookArray.include?(webhookDef['name'])
          space_sdk.update_webhook_on_kapp(kapp['slug'], webhookDef['name'], webhookDef)
        else
          space_sdk.add_webhook_on_kapp(kapp['slug'], webhookDef)
        end
        sourceWebhookArray.push(webhookDef['name'])
    }   
  
    # ------------------------------------------------------------------------------
    # Delete Kapp Webhooks
    # ------------------------------------------------------------------------------
    destinationWebhookArray.each { | attribute |
      if vars["options"]["delete"] && !sourceWebhookArray.include?(attribute)
          space_sdk.delete_webhook_on_kapp(kapp['slug'],attribute)
      end
    }
  end                                                        


  # ------------------------------------------------------------------------------
  # Add Kapp Forms
  # ------------------------------------------------------------------------------
  
  if (forms = Dir["#{core_path}/space/kapps/#{kapp['slug']}/forms/*.json"]).length > 0 
    sourceForms = [] #From import data
    destinationForms = (space_sdk.find_forms(kapp['slug']).content['forms'] || {}).map{ |form| form['slug']}
    forms.each { |form|
      properties = File.read(form)
      form = JSON.parse(properties)
      sourceForms.push(form['slug'])
      if destinationForms.include?(form['slug'])
        space_sdk.update_form(kapp['slug'] ,form['slug'], form)
      else   
        space_sdk.add_form(kapp['slug'], form)
      end
    }
    # ------------------------------------------------------------------------------
    # delete forms
    # ------------------------------------------------------------------------------
    destinationForms.each { |slug|
      if vars["options"]["delete"] && !sourceForms.include?(slug)
        #Delete form is disabled
        #space_sdk.delete_form(kapp['slug'], slug)
      end
    } 
  end
  
  # ------------------------------------------------------------------------------
  # Import Kapp Form Data
  # ------------------------------------------------------------------------------
  Dir["#{core_path}/space/kapps/#{kapp['slug']}/forms/**/submissions*.ndjson"].sort.each { |filename|
    dir = File.dirname(filename)
    form_slug = filename.match(/forms\/(.+)\/submissions\.ndjson/)[1]
    
    # This code could delete all submissions form the form before importing new data
    # It is commented out because it could be dangerous to have in place and the delete_submission method doesn't exist currently.
    #(space_sdk.find_all_form_submissions(kapp['slug'], form_slug).content['submissions'] || []).each { |submission|
    #  space_sdk.delete_submission(submission['id'])
    #}
    
    File.readlines(filename).each { |line|
      submission = JSON.parse(line) 
      submission["values"].map { |field, value|
          # if the value contains an array of files
          if value.is_a?(Array) && !value.empty? && value.first.is_a?(Hash) && value.first.has_key?('path')
            value.map.with_index { |file, index|
              # add 'path' key to the attribute value indicating the location of the attachment
              file['path'] = "#{dir}#{file['path']}"
            }
          end
      }
      body = { 
        "values" => submission["values"],
        "coreState" => submission["coreState"]
      }
      space_sdk.add_submission(yml['slug'], form_slug, body).content
    }
  }
  # ------------------------------------------------------------------------------
  # Add Kapp Web APIs
  # ------------------------------------------------------------------------------   
  sourceWebApisArray = []
  destinationWebApisArray = (space_sdk.find_kapp_webapis(kapp['slug']).content['webApis'] || {}).map { |definition|  definition['slug']}
  Dir["#{core_path}/space/kapps/#{kapp['slug']}/webApis/*"].each { |webApi|
    body = JSON.parse(File.read(webApi))
    if destinationWebApisArray.include?(body['slug'])
    space_sdk.update_kapp_webapi(kapp['slug'], body['slug'], body)
    else
    space_sdk.add_kapp_webapi(kapp['slug'], body)
    end
    sourceWebApisArray.push(body['slug'])
  }
  # ------------------------------------------------------------------------------
  # Delete Kapp Web APIs
  # ------------------------------------------------------------------------------
  destinationWebApisArray.each { | webApi |
    if vars["options"]["delete"] && !sourceWebApisArray.include?(webApi)
        space_sdk.delete_kapp_webapi(kapp['slug'], webApi)
    end
  }
}

# ------------------------------------------------------------------------------
# task
# ------------------------------------------------------------------------------

task_sdk = KineticSdk::Task.new({
  app_server_url: "#{vars["task"]["server_url"]}",
  username: vars["task"]["service_user_username"],
  password: vars["task"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{task_path}" })
})

# ------------------------------------------------------------------------------
# task import
# ------------------------------------------------------------------------------

logger.info "Importing the task components for the \"#{template_name}\" template."
logger.info "  importing with api: #{task_sdk.api_url}"

# ------------------------------------------------------------------------------
# task handlers
# ------------------------------------------------------------------------------

# import handlers forcing overwrite
task_sdk.import_handlers(true) 

# ------------------------------------------------------------------------------
# Import Task Trees and Routines
# ------------------------------------------------------------------------------

# import routines and force overwrite
task_sdk.import_routines(true)
# import trees and force overwrite
task_sdk.import_trees(true)



# ------------------------------------------------------------------------------
# import task categories
# ------------------------------------------------------------------------------

sourceCategories = [] #From import data
destinationCategories = (task_sdk.find_categories().content['categories'] || {}).map{ |category| category['name']}

Dir["#{task_path}/categories/*.json"].each { |file|
  category = JSON.parse(File.read(file))
  sourceCategories.push(category['name'])
  if destinationCategories.include?(category['name'])
    task_sdk.update_category(category['name'], category)
  else
    task_sdk.add_category(category)
  end
}

# ------------------------------------------------------------------------------
# delete task categories
# ------------------------------------------------------------------------------

destinationCategories.each { |category|
  if vars["options"]["delete"] && !sourceCategories.include?(category)
    task_sdk.delete_category(category)
  end
} 

# ------------------------------------------------------------------------------
# import task policy rules
# ------------------------------------------------------------------------------

destinationPolicyRuleArray = task_sdk.find_policy_rules().content['policyRules']
sourcePolicyRuleArray = Dir["#{task_path}/policyRules/*.json"].map{ |file| 
    rule = JSON.parse(File.read(file))
    {"name" => rule['name'], "type" => rule['type']}
  }

Dir["#{task_path}/policyRules/*.json"].each { |file|
  rule = JSON.parse(File.read(file))
  if !destinationPolicyRuleArray.find {|dest_rule| dest_rule['name']==rule['name'] && dest_rule['type']==rule['type'] }.nil?
    task_sdk.update_policy_rule(rule.slice('type', 'name'), rule)
  else
    task_sdk.add_policy_rule(rule)
  end
}

# ------------------------------------------------------------------------------
# delete task policy rules
# ------------------------------------------------------------------------------
destinationPolicyRuleArray.each { |rule|
  if vars["options"]["delete"] && sourcePolicyRuleArray.find {|source_rule| source_rule['name']==rule['name'] && source_rule['type']==rule['type'] }.nil?
    task_sdk.delete_policy_rule(rule)
  end
}

# ------------------------------------------------------------------------------
# Delete Trees and Routines not in the Source Data
# ------------------------------------------------------------------------------

# identify Trees and Routines on destination
destinationtrees = []
trees = task_sdk.find_trees().content
(trees['trees'] || []).each { |tree|
  destinationtrees.push( tree['title'] )
}

# identify Routines in source data
sourceTrees = []
Dir["#{task_path}/routines/*.xml"].each {|routine| 
  doc = Document.new(File.new(routine))
  root = doc.root
  sourceTrees.push("#{root.elements["taskTree/name"].text}")
}
# identify trees in source data
Dir["#{task_path}/sources/*"].each {|source| 
  if File.directory? source
    Dir["#{source}/trees/*.xml"].each { |tree|
      doc = Document.new(File.new(tree))
      root = doc.root
      tree = "#{root.elements["sourceName"].text} :: #{root.elements["sourceGroup"].text} :: #{root.elements["taskTree/name"].text}"
      sourceTrees.push(tree)
    }
  end
}

# Delete the extra tress and routines on the source  
destinationtrees.each { | tree |
  if vars["options"]["delete"] && !sourceTrees.include?(tree)
    treeDef = tree.split(' :: ')
    task_sdk.delete_tree(  tree  )
  end
}

# ------------------------------------------------------------------------------
# complete
# ------------------------------------------------------------------------------

logger.info "Finished importing the \"#{template_name}\" forms."
