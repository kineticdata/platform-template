# NOTES
# This is a migration tool not an installation tool.  There are certain expectations that the destination is configured and working.
# Agent Server(s) must be added ahead of migration.  /space/settings/platformComponents/agents
# Task Server must be added ahead of migration.  /space/settings/platformComponents/task
# Task Sources must be manually maintained
# Bridges must be added ahead of migration.  /space/plugins/bridges
# Agent Handlers are not migrated by design.  They intentionally must be manually added.
# Teams are not deleted from destination.  It could be too dangerous to delete them.

# TODO
#Have better validation/notification if you cannot connect (Certificate issue)

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
#require_relative './bundle/bundler/setup'
require 'logger'      #For System Logging
require 'json'
require 'rexml/document'
require 'optparse'    #For argument parsing
# require 'kinetic_sdk'
require 'find'        #For config list building
require 'io/console'  #For password request
require 'base64'      #For pwd encoding
require 'concurrent-ruby'


require 'kinetic_sdk'



def import_space()
  template_name = "platform-template"
  $pwdFields = ["core","task"]


  $logger = Logger.new(STDERR)
  $logger.level = Logger::INFO
  $logger.formatter = proc do |severity, datetime, progname, msg|
    date_format = datetime.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
    "[#{date_format}] #{severity}: #{msg}\n"
  end

  #########################################
  # Determine the Present Working Directory
  pwd = File.expand_path(File.dirname(__FILE__))

  # ARGV << '-h' if ARGV.empty?

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

  max_threads = 10
  $pool = Concurrent::FixedThreadPool.new(max_threads) 
  $mutex = Mutex.new 
  kapps_array = []
  kpromises = []





  #End method

  # determine the directory paths
  platform_template_path = File.dirname(File.expand_path(__FILE__))
  config_folder_path = File.join(platform_template_path,'config')

  if options["CONFIG_FILE"].nil?
    options["CONFIG_FILE"] = config_selection(config_folder_path)
  end

  $logger.info "Installing gems for the \"#{template_name}\" template."
  Dir.chdir(platform_template_path) { system("bundle", "install") }

  vars = {}
  file = "#{platform_template_path}/#{options['CONFIG_FILE']}"

  # Check if configuration file exists
  $logger.info "Validating configuration file."
  begin
    if File.exist?(file) != true
      file = "#{config_folder_path}/#{options['CONFIG_FILE']}"
      if File.exist?(file) != true
        raise "The file \"#{options['CONFIG_FILE']}\" does not exist in the base or config directories."
      end
    end
  rescue => error
    $logger.info error
    $logger.info "Exiting..."
    exit
  end

  # Read the config file specified in the command line into the variable ""
  begin
    vars.merge!( YAML.load(File.read(file)) )
  rescue => error
    $logger.info "Error loading YAML configuration"
    $logger.info error
    $logger.info "Exiting..."
    gets
    exit
  end
  $logger.info "Configuration file passed validation."

  vars["options"] ||= {}

  ValidatePWD(file, vars)
  #Will confirm there is a valid, encoded password and decode. Otherwise it will prompt/encode pwd and return decoded variant
  vars["core"]["service_user_password"] = DecodePWD(file, vars,"core")
  vars["task"]["service_user_password"] = DecodePWD(file, vars, "task")


  if vars["core"]["service_user_password"].empty? || vars["core"]["service_user_password"].nil?
    puts "Core password is blank! Password required. Exiting..."
    gets
    exit
  end
  if vars["task"]["service_user_password"].empty? || vars["task"]["service_user_password"].nil?
    puts "Task password is blank! Password required. Exiting..."
    gets
    exit
  end



  # Set http_options based on values provided in the config file.
  http_options = (vars["http_options"] || {}).each_with_object({}) do |(k,v),result|
    result[k.to_sym] = v
  end

  #Config exports folder exists, if not then create
  if !File.directory?(File.join(platform_template_path,"exports"))
    Dir.mkdir(File.join(platform_template_path, "exports"))
  end

  #Setting core paths utilzing variables - Check old_space_slug -> space_slug -> space_name
  if !vars['core']['old_space_slug'].nil?
    folderName = vars['core']['old_space_slug']
  elsif !vars['core']['space_slug'].nil?
    folderName = vars['core']['space_slug']
  elsif !vars['core']['space_name'].nil?
    folderName = vars['core']['space_name']
  else
    puts "No space slug or name provided! Please provide one in order to export..."
    gets
    exit
  end
  core_path = File.join(platform_template_path, "exports", folderName, "core")
  task_path = File.join(platform_template_path, "exports", folderName, "task")

  # Output the yml file config
  $logger.info "Output of Configuration File: \r #{JSON.pretty_generate(vars)}"

  $logger.info "Setting up the SDK"

  $space_sdk = KineticSdk::Core.new({
    space_server_url: vars["core"]["server_url"],
    space_slug: vars["core"]["space_slug"],
    username: vars["core"]["service_user_username"],
    password: vars["core"]["service_user_password"],
    options: http_options.merge({ export_directory: "#{core_path}" })
  })

  puts "Are you sure you want to perform an import of data from #{folderName} to #{vars["core"]["server_url"]}? [Y/N]"
  STDOUT.flush
  case (gets.downcase.chomp)
  when 'y'
    puts "Continuing Import"
    STDOUT.flush
  else
    abort "Exiting Import"
  end

  

  import_bridge_models(core_path,vars)

  # ------------------------------------------------------------------------------
  # delete bridge models
  # Delete any Bridges from the destination which are missing from the import data
  # ------------------------------------------------------------------------------
  import_space_web_apis(core_path)

  # ------------------------------------------------------------------------------
  # delete space teams
  # TODO: A method doesn't exist for deleting the team
  # ------------------------------------------------------------------------------

  # ------------------------------------------------------------------------------
  # import kapp data
  # ------------------------------------------------------------------------------

  Dir["#{core_path}/space/kapps/*"].each { |file|
    kpromises << Concurrent::Promise.execute(executor: $pool) do
      begin
        kapp_slug = file.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}.last.gsub('.json','')
        already_processed = $mutex.synchronize do
          if kapps_array.include?(kapp_slug)
            true
          else
            kapps_array.push(kapp_slug)
            false
          end
        end
        next if already_processed
        kapp = {}
        kapp['slug'] = kapp_slug # set kapp_slug
          
        if File.file?(file) or ( File.directory?(file) and File.file?(file = "#{file}.json") ) # If the file is a file or a dir with a corresponding json file
          kapp = JSON.parse( File.read(file) )
          kappExists = $space_sdk.find_kapp(kapp['slug']).code.to_i == 200  
          if kappExists
            $space_sdk.update_kapp(kapp['slug'], kapp)
          else
            $space_sdk.add_kapp(kapp['name'], kapp['slug'], kapp)
          end
        end 


        import_kapp_attribute_definitions(core_path, kapp, vars)
        import_kapp_form_attribute_definitions(core_path, kapp, vars)
        import_kapp_form_type_definitions(core_path, kapp, vars)

        import_kapp_security_policy_definitions(core_path, kapp, vars)

        # ------------------------------------------------------------------------------
        # Migrate Kapp Categories
        # ------------------------------------------------------------------------------
        import_kapp_categories(core_path, kapp, vars)

        

        # ------------------------------------------------------------------------------
        # import space webhooks
        # ------------------------------------------------------------------------------
        sourceSpaceWebhooksArray = []
        destinationSpaceWebhooksNames = ($space_sdk.find_webhooks_on_space({"include"=>"details"}).content['webhooks'] || {}).map { |webhook| webhook['name'] }

        Dir["#{core_path}/space/webhooks/*.json"].each { |file|
          webhook = JSON.parse(File.read(file))
          if destinationSpaceWebhooksNames.include?(webhook['name'])
            $space_sdk.update_webhook_on_space(webhook['name'], webhook)
          else
            $space_sdk.add_webhook_on_space(webhook)
          end
          sourceSpaceWebhooksArray.push(webhook['name'])
        }

        # ------------------------------------------------------------------------------
        # delete space webhooks
        # TODO: A method doesn't exist for deleting the webhook
        # ------------------------------------------------------------------------------

        destinationSpaceWebhooksNames.each do |webhook|
          if vars["options"]["delete"] && !sourceSpaceWebhooksArray.include?(webhook)
            $space_sdk.delete_webhook_on_space(webhook)
          end
        end

        # ------------------------------------------------------------------------------
        # Migrate Kapp Webhooks
        # ------------------------------------------------------------------------------
        sourceWebhookArray = []
        webhooks_on_kapp = $space_sdk.find_webhooks_on_kapp(kapp['slug']) 
        
        if webhooks_on_kapp.code=="200" 
          destinationWebhookArray = (webhooks_on_kapp.content['webhooks'] || {}).map { |definition|  definition['name']}
          Dir["#{core_path}/space/kapps/#{kapp['slug']}/webhooks/*.json"].each{ |webhookFile|
              webhookDef = JSON.parse(File.read(webhookFile))
              if destinationWebhookArray.include?(webhookDef['name'])
                $space_sdk.update_webhook_on_kapp(kapp['slug'], webhookDef['name'], webhookDef)
              else
                $space_sdk.add_webhook_on_kapp(kapp['slug'], webhookDef)
              end
              sourceWebhookArray.push(webhookDef['name'])
          }   
        
          # ------------------------------------------------------------------------------
          # Delete Kapp Webhooks
          # ------------------------------------------------------------------------------
          destinationWebhookArray.each { | attribute |
            if vars["options"]["delete"] && !sourceWebhookArray.include?(attribute)
                $space_sdk.delete_webhook_on_kapp(kapp['slug'],attribute)
            end
          }
        end                                                        


        
        import_forms(core_path,kapp,vars)
        

        ##TODO - Convert to csv upload
        ## PATCH https://playground-travis-wiese.kinopsdev.io/app/api/v1/kapps/kapp1/forms/f1/submissions?import
        ##

        # ------------------------------------------------------------------------------
        # Import Kapp Form Data
        # ------------------------------------------------------------------------------
        
        import_kapp_form_data(core_path, kapp)
        import_kapp_web_apis(core_path, kapp, vars)
      rescue => e
        slug_for_log = (defined?(kapp) && kapp.is_a?(Hash) ? kapp['slug'] : nil) || (defined?(kapp_slug) ? kapp_slug : 'unknown')
        $mutex.synchronize do
          $logger.error "Error processing kapp '#{slug_for_log}': #{e.class}: #{e.message}"
          $logger.error e.backtrace.join("\n")
        end
      end
    end

  } 
  kpromises.each(&:wait!)

    
  #End Kapp loop

  # ------------------------------------------------------------------------------
  # task
  # ------------------------------------------------------------------------------

  $task_sdk = KineticSdk::Task.new({
    app_server_url: "#{vars["task"]["server_url"]}",
    username: vars["task"]["service_user_username"],
    password: vars["task"]["service_user_password"],
    options: http_options.merge({ export_directory: "#{task_path}" })
  })

  # ------------------------------------------------------------------------------
  # task import
  # ------------------------------------------------------------------------------

  $logger.info "Importing the task components for the \"#{template_name}\" template."
  $logger.info "  importing with api: #{$task_sdk.api_url}"

  # ------------------------------------------------------------------------------
  # task handlers
  # ------------------------------------------------------------------------------

  # import handlers forcing overwrite
  $task_sdk.import_handlers_threaded(true) 

  # ------------------------------------------------------------------------------
  # Import Task Trees and Routines
  # ------------------------------------------------------------------------------

  # import routines and force overwrite
  $task_sdk.import_routines_threaded(true)
  # import trees and force overwrite
  $task_sdk.import_trees_threaded(true)



  # ------------------------------------------------------------------------------
  # import task categories
  # ------------------------------------------------------------------------------

  sourceCategories = [] #From import data
  destinationCategoryNames = ($task_sdk.find_categories().content['categories'] || {}).map{ |category| category['name'] }

  Dir["#{task_path}/categories/*.json"].each { |file|
    category = JSON.parse(File.read(file))

    sourceCategories.push(category['name'])

    if destinationCategoryNames.include?(category['name'])
      $task_sdk.update_category(category['name'], category)
    else
      $task_sdk.add_category(category)
    end
  }

  # ------------------------------------------------------------------------------
  # delete task categories
  # ------------------------------------------------------------------------------

  destinationCategoryNames.each { |category|
    if vars["options"]["delete"] && !sourceCategories.include?(category)
      $task_sdk.delete_category(category)
    end
  }

  # ------------------------------------------------------------------------------
  # import task policy rules
  # ------------------------------------------------------------------------------

  destinationPolicyRuleArray = $task_sdk.find_policy_rules().content['policyRules']
  sourcePolicyRuleArray = Dir["#{task_path}/policyRules/*.json"].map{ |file| 
      rule = JSON.parse(File.read(file))
      {"name" => rule['name'], "type" => rule['type']}
    }

  Dir["#{task_path}/policyRules/*.json"].each { |file|
    rule = JSON.parse(File.read(file))
    if !destinationPolicyRuleArray.find {|dest_rule| dest_rule['name']==rule['name'] && dest_rule['type']==rule['type'] }.nil?
      $task_sdk.update_policy_rule(rule.slice('type', 'name'), rule)
    else
      $task_sdk.add_policy_rule(rule)
    end
  }

  # ------------------------------------------------------------------------------
  # delete task policy rules
  # ------------------------------------------------------------------------------
  destinationPolicyRuleArray.each { |rule|
    if vars["options"]["delete"] && sourcePolicyRuleArray.find {|source_rule| source_rule['name']==rule['name'] && source_rule['type']==rule['type'] }.nil?
      $task_sdk.delete_policy_rule(rule)
    end
  }

  # ------------------------------------------------------------------------------
  # Delete Trees and Routines not in the Source Data
  # ------------------------------------------------------------------------------

  # identify Trees and Routines on destination
  destinationtrees = []
  trees = $task_sdk.find_trees().content
  (trees['trees'] || []).each { |tree|
    destinationtrees.push( tree['title'] )
  }

  # identify Routines in source data
  begin
    sourceTrees = []
    Dir["#{task_path}/routines/*.xml"].each {|routine|
      doc = REXML::Document.new(File.read(routine))
      root = doc.root
      sourceTrees.push("#{root.elements["taskTree/name"].text}")
    }
  rescue
    $logger.error "Error while identifying routines"
  end

  begin
    # identify trees in source data
    Dir["#{task_path}/sources/*"].each {|source| 
      if File.directory? source
        Dir["#{source}/trees/*.xml"].each { |tree|
          doc = REXML::Document.new(File.read(tree))
          root = doc.root
          tree = "#{root.elements["sourceName"].text} :: #{root.elements["sourceGroup"].text} :: #{root.elements["taskTree/name"].text}"
          sourceTrees.push(tree)
        }
      end
    }
  rescue
    $logger.error "Error identifying trees"
  end

  begin
    # Delete the extra tress and routines on the source  
    destinationtrees.each { | tree |
      if vars["options"]["delete"] && !sourceTrees.include?(tree)
        treeDef = tree.split(' :: ')
        $task_sdk.delete_tree(  tree  )
      end
    }
  rescue
    $logger.error "Error deleting extra trees/routines on source"
  end


  # Import v6 workflows as these are not not the same as Trees and Routines
  $logger.info "Importing workflows"
  $space_sdk.import_workflows(vars["core"]["space_slug"])

  # ------------------------------------------------------------------------------
  # complete
  # ------------------------------------------------------------------------------

  $logger.info "Finished importing the \"#{template_name}\" forms."

  $pool.shutdown
  $pool.wait_for_termination
  
end






  ################################################################################
  # Import Methods
  ################################################################################

  # ------------------------------------------------------------------------------
  # Update Space Attributes
  # ------------------------------------------------------------------------------

  def update_space_attributes(core_path)
    sourceSpaceAttributeArray = []
    destinationSpaceAttributeArray = ($space_sdk.find_space_attribute_definitions().content['spaceAttributeDefinitions']|| {}).map { |definition|  definition['name']}

    if File.file?(file = "#{core_path}/space/spaceAttributeDefinitions.json")
      spaceAttributeDefinitions = JSON.parse(File.read(file))

      spaceAttributeDefinitions.each { |attribute|
          if destinationSpaceAttributeArray.include?(attribute['name'])
            $space_sdk.update_space_attribute_definition(attribute['name'], attribute)
          else
            $space_sdk.add_space_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
          end
          sourceSpaceAttributeArray.push(attribute['name'])
      }  
    end  
    destinationSpaceAttributeArray.each { | attribute |
      if vars["options"]["delete"] && !sourceSpaceAttributeArray.include?(attribute)
          $space_sdk.delete_space_attribute_definition(attribute)
      end
    }
  end




  # ------------------------------------------------------------------------------
  # Update User Attributes
  # ------------------------------------------------------------------------------
  def update_user_attributes( core_path)
    sourceUserAttributeArray = []
    destinationUserAttributeArray = ($space_sdk.find_user_attribute_definitions().content['userAttributeDefinitions'] || {}).map { |definition|  definition['name']}

    if File.file?(file = "#{core_path}/space/userAttributeDefinitions.json")
      userAttributeDefinitions = JSON.parse(File.read(file))
      userAttributeDefinitions.each { |attribute|
          if destinationUserAttributeArray.include?(attribute['name'])
            $space_sdk.update_user_attribute_definition(attribute['name'], attribute)
          else
            $space_sdk.add_user_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
          end
          sourceUserAttributeArray.push(attribute['name'])
      }  
    end

    destinationUserAttributeArray.each { | attribute |
      if vars["options"]["delete"] && !sourceUserAttributeArray.include?(attribute)
          $space_sdk.delete_user_attribute_definition(attribute)
      end
    }
  end

  # ------------------------------------------------------------------------------
  # Update User Profile Attributes
  # ------------------------------------------------------------------------------
  def update_user_profile_attributes(core_path)
    sourceUserProfileAttributeArray = []
    destinationUserProfileAttributeArray = ($space_sdk.find_user_profile_attribute_definitions().content['userProfileAttributeDefinitions'] || {}).map { |definition|  definition['name']}

    if File.file?(file = "#{core_path}/space/userProfileAttributeDefinitions.json")
      userProfileAttributeDefinitions = JSON.parse(File.read(file))

      userProfileAttributeDefinitions.each { |attribute|
          if destinationUserProfileAttributeArray.include?(attribute['name'])
            $space_sdk.update_user_profile_attribute_definition(attribute['name'], attribute)
          else
            $space_sdk.add_user_profile_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
          end
          sourceUserProfileAttributeArray.push(attribute['name'])
      }  
    end  

    destinationUserProfileAttributeArray.each { | attribute |
      if vars["options"]["delete"] && !sourceUserProfileAttributeArray.include?(attribute)
          $space_sdk.delete_user_profile_attribute_definition(attribute)
      end
    }
  end



  # ------------------------------------------------------------------------------
  # Update Team Attributes
  # ------------------------------------------------------------------------------
  def update_team_attributes( core_path)
    sourceTeamAttributeArray = []
    destinationTeamAttributeArray = ($space_sdk.find_team_attribute_definitions().content['teamAttributeDefinitions']|| {}).map { |definition|  definition['name']}

    if File.file?(file = "#{core_path}/space/teamAttributeDefinitions.json")
      teamAttributeDefinitions = JSON.parse(File.read(file))
      teamAttributeDefinitions.each { |attribute|
          if destinationTeamAttributeArray.include?(attribute['name'])
            $space_sdk.update_team_attribute_definition(attribute['name'], attribute)
          else
            $space_sdk.add_team_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
          end
          sourceTeamAttributeArray.push(attribute['name'])
      }  
    end

    destinationTeamAttributeArray.each { | attribute |
      if vars["options"]["delete"] && !sourceTeamAttributeArray.include?(attribute)
          $space_sdk.delete_team_attribute_definition(attribute)
      end
    }
  end


  # ------------------------------------------------------------------------------
  # Update Datastore Attributes
  # ------------------------------------------------------------------------------
  def update_datastore_attributes( core_path)
    sourceDatastoreAttributeArray = []
    destinationDatastoreAttributeArray =($space_sdk.find_datastore_form_attribute_definitions().content['datastoreFormAttributeDefinitions'] || {}).map { |definition|  definition['name']}

    if File.file?(file = "#{core_path}/space/datastoreFormAttributeDefinitions.json")
      datastoreFormAttributeDefinitions = JSON.parse(File.read(file))
      datastoreFormAttributeDefinitions.each { |attribute|
          if destinationDatastoreAttributeArray.include?(attribute['name'])
            $space_sdk.update_datastore_form_attribute_definition(attribute['name'], attribute)
          else
            $space_sdk.add_datastore_form_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
          end
          sourceDatastoreAttributeArray.push(attribute['name'])
      }  
    end

    destinationDatastoreAttributeArray.each { | attribute |
      if vars["options"]["delete"] && !sourceDatastoreAttributeArray.include?(attribute)
          #Delete form is disabled
          #$space_sdk.delete_datastore_form_attribute_definition(attribute)
      end
    }
  end


  # ------------------------------------------------------------------------------
  # Update Security Policy
  # ------------------------------------------------------------------------------
  def update_security_policy( core_path)
    sourceSecurityPolicyArray = []
    destinationSecurityPolicyArray = ($space_sdk.find_space_security_policy_definitions().content['securityPolicyDefinitions'] || {}).map { |definition|  definition['name']}

    if File.file?(file = "#{core_path}/space/securityPolicyDefinitions.json")
      securityPolicyDefinitions = JSON.parse(File.read(file))
      securityPolicyDefinitions.each { |attribute|
          if destinationSecurityPolicyArray.include?(attribute['name'])
            $space_sdk.update_space_security_policy_definition(attribute['name'], attribute)
          else
            $space_sdk.add_space_security_policy_definition(attribute)
          end
          sourceSecurityPolicyArray.push(attribute['name'])
      }  
    end

    destinationSecurityPolicyArray.each { | attribute |
      if vars["options"]["delete"] && !sourceSecurityPolicyArray.include?(attribute)
          $space_sdk.delete_space_security_policy_definition(attribute)
      end
    }
  end

  # ------------------------------------------------------------------------------
  # Delete Space Web APIs
  # Delete any Web APIs from the destination which are missing from the import data
  # ------------------------------------------------------------------------------
  def delete_space_web_apis( core_path)
    destinationSpaceWebApisArray.each { | webApi |
      if vars["options"]["delete"] && !sourceSpaceWebApisArray.include?(webApi)
          $space_sdk.delete_space_webapi(webApi)
      end
    }
  end


  # ------------------------------------------------------------------------------
  # import datastore forms
  # ------------------------------------------------------------------------------

  def import_datastore_forms( core_path)
    $logger.info "Importing datastore forms for #{vars["core"]["space_slug"]}"
    destinationDatastoreForms = [] #From destination server
    sourceDatastoreForms = [] #From import data
    destinationDatastoreForms = fetch_all_datastore_forms.map { |datastore| datastore['slug'] }
    Dir["#{core_path}/space/datastore/forms/*.json"].each { |datastore|
      body = JSON.parse(File.read(datastore))
      sourceDatastoreForms.push(body['slug'])
      if destinationDatastoreForms.include?(body['slug'])
        $space_sdk.update_datastore_form(body['slug'], body)
      else
        $space_sdk.add_datastore_form(body)
      end
    }
  end


  # ------------------------------------------------------------------------------
  # delete datastore forms
  # Delete any form from the destination which are missing from the import data
  # ------------------------------------------------------------------------------
  def delete_datastore_forms(core_path)
    destinationDatastoreForms.each { |datastore_slug|
      if vars["options"]["delete"] && !sourceDatastoreForms.include?(datastore_slug)
        $space_sdk.delete_datastore_form(datastore_slug)
      end
    }
  end



  # ------------------------------------------------------------------------------
  # Import Datastore Data
  # ------------------------------------------------------------------------------

  def import_datastore_data( core_path)
    Dir["#{core_path}/space/datastore/forms/**/submissions*.ndjson"].sort.each { |filename|
      dir = File.dirname(filename)
      form_slug = filename.match(/forms\/(.+)\/submissions\.ndjson/)[1]
      ($space_sdk.find_all_form_datastore_submissions(form_slug).content['submissions'] || []).each { |submission|
        $space_sdk.delete_datastore_submission(submission['id'])
      }
      File.foreach(filename) { |line|
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
        $space_sdk.add_datastore_submission(form_slug, body).content
      }
    }
  end

  # ------------------------------------------------------------------------------
  # import space teams
  # ------------------------------------------------------------------------------

  def import_space_teams( core_path)
    
    if (teams = Dir["#{core_path}/space/teams/*.json"]).length > 0 
      sourceTeamArray = []
      destinationTeamsArray = ($space_sdk.find_teams({"include"=>"details"}).content['teams'] || {}).map{ |team| {"slug" => team['slug'], "name"=>team['name'], "updatedAt"=>team['updatedAt']} }
      teams.each{ |team|
        body = JSON.parse(File.read(team))
        destinationTeam = destinationTeamsArray.find {|destination_team| destination_team['slug'] == body['slug']}
        if !destination_team.nil?
          #If no updates, skip
          if destination_team['updatedAt'] != team['updatedAt']
            $space_sdk.update_team(body['slug'], body)
          else

          end

        else
          $space_sdk.add_team(body)
        end
        #Add Attributes to the Team
        (body['attributes'] || []).each{ | attribute |
        $space_sdk.add_team_attribute(body['name'], attribute['name'], attribute['values'])
        }
        sourceTeamArray.push({'name' => body['name'], 'slug'=>body['slug']} )
      }
      destinationTeamsArray.each { |team|
        #if !SourceTeamArray.include?(team)
        if sourceTeamArray.find {|source_team| source_team['slug'] == team['slug']  }.nil?
          #Delete has been disabled.  It is potentially too dangerous to include w/o advanced knowledge.
          #$space_sdk.delete_team(team['slug'])
        end
      }
    end
  end

  # ------------------------------------------------------------------------------
  # Import Kapp Categories
  # ------------------------------------------------------------------------------
  def import_kapp_categories(core_path, kapp, vars)
    if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/categories.json")
      sourceCategoryArray = []
      destinationCategoryArray = ($space_sdk.find_categories(kapp['slug']).content['categories'] || {}).map { |definition|  definition['slug']}
      categories = JSON.parse(File.read(file))
      (categories || []).each { |attribute|
        if destinationCategoryArray.include?(attribute['slug'])
          $space_sdk.update_category_on_kapp(kapp['slug'], attribute['slug'], attribute)
        else
          $space_sdk.add_category_on_kapp(kapp['slug'], attribute)
        end
        sourceCategoryArray.push(attribute['slug'])
      }
      # ------------------------------------------------------------------------------
      # Delete Kapp Categories
      # ------------------------------------------------------------------------------
      
      destinationCategoryArray.each { | attribute |
        if vars["options"]["delete"] && !sourceCategoryArray.include?(attribute)
            $space_sdk.delete_category_on_kapp(kapp['slug'],attribute)
        end
      }
    end
  end
  ################################################################################
  # Helpers
  ################################################################################

  #Configuration Selection
  def config_selection(config_folder_path)

    #Ensure config folder exists
    if !File.directory?(config_folder_path)
      $logger.info "Config folder not found at #{config_folder_path}"
      puts "Cannot find config folder!"
      puts "Exiting..."
      gets
      exit
    end

    # #Determine Config file to use
    config_exts = ['.yaml','.yml']
    configArray = []
    $logger.info "Checking #{config_folder_path} for config files"
    #Check config folder for yaml/yml files containing the word 'import'
    begin
      Find.find("#{config_folder_path}/") do |file|
        configArray.append(File.basename(file)) if config_exts.include?(File.extname(file)) && (File.basename(file).include?('import'))
      end
    rescue => error
      #No config files found in config folder
      $logger.error "Error finding default config file path!"
      $logger.error "Error reported: #{error}"
      puts "Cannot find config files in default path! (#{pwd})"
      puts "Exiting script..."
      gets
      exit
    end
    $logger.info "Found config files"

    #Print config file options with number indicators to select
    puts "Select your config file"
    configArray.each_with_index do |cFile, index|
      puts "#{index+1}) #{cFile}" 
    end
    $logger.info "Select section"
    begin
      print "Selection (0 to repeat options): "
      sel = gets.chomp.to_i
      begin
        if sel === 0
          configArray.each_with_index do |cFile, index|
            puts "#{index+1}) #{cFile}" 
          end
          next
        end
        configFile = configArray[sel-1]
        $logger.info "Option #{sel} - #{configFile}"
        break
      rescue
        $logger.info "Error selecting config file! Exiting..."
        puts "Error selecting config file!"
        puts "Exiting..."
        gets
        exit
      end
    end while true
    return configFile
  end
  
  #Check if nil/unencoded and update accordingly
def SecurePWD(file,vars,pwdAttribute)
  #If no pwd, then ask for one, otherwise take current string that was not found to be B64 and convert
  if vars[pwdAttribute]["service_user_password"].nil?
    password = IO::console.getpass "Enter Password(#{pwdAttribute}): "
  else
    password = vars[pwdAttribute]["service_user_password"]
  end
  enc = Base64.strict_encode64(password)
  vars[pwdAttribute]["service_user_password"] = enc.to_s
  begin
    fileObj = File.open(file, 'w') 
    puts "Updated pwd in #{pwdAttribute} to #{enc}"
    fileObj.write vars.to_yaml
    #{ |f| f.write vars.to_yaml }
  rescue ArgumentError
    $logger.error("There was an error while updating variables file:")
    $logger.error(ArgumentError)
  ensure
    fileObj.close
  end
end

#Decode password to utilize
def DecodePWD(file, vars, pwdLoc)
  pwdAttribute = vars[pwdLoc]["service_user_password"]
  return Base64.decode64(pwdAttribute)
end

#Confirm passwords exist and are in a proper format, call SecurePWD for any exceptions
def ValidatePWD(file, vars)
  $pwdFields.each do |field|
    t = vars[field]["service_user_password"]
    #See if not a string, not encoded, or default <PASSWORD>
    if !t.is_a?(String) || Base64.strict_encode64(Base64.decode64(t)) != t || t === "<PASSWORD>"
      puts "Updating password #{t}"
      SecurePWD(file, vars, field)
    end
  end
end
def convert_json_to_csv(json_file)
    csv_file = json_file.gsub("ndjson","csv")
    CSV.open(csv_file, 'w') do |csv|
      File.foreach(json_file).with_index do |line, index|
        record = JSON.parse(line)
        
        # Write header on first row
        csv << record.keys if index == 0
        
        # Write values
        csv << record.values
      end
    end
  end

  def compare_forms(kapp_slug, old_form)

  end

  # ------------------------------------------------------------------------------
  # Migrate Kapp Form Attribute Definitions
  # ------------------------------------------------------------------------------
  def import_kapp_form_attribute_definitions(core_path, kapp, vars)
    if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/formAttributeDefinitions.json")
      sourceFormAttributeArray = []
      destinationFormAttributeArray = ($space_sdk.find_form_attribute_definitions(kapp['slug']).content['formAttributeDefinitions'] || {}).map { |definition|  definition['name']}
      formAttributeDefinitions = JSON.parse(File.read(file))
      (formAttributeDefinitions || []).each { |attribute|
          if destinationFormAttributeArray.include?(attribute['name'])
            $space_sdk.update_form_attribute_definition(kapp['slug'], attribute['name'], attribute)
          else
            $space_sdk.add_form_attribute_definition(kapp['slug'], attribute['name'], attribute['description'], attribute['allowsMultiple'])
          end
          sourceFormAttributeArray.push(attribute['name'])
      }   
      # ------------------------------------------------------------------------------
      # Delete Kapp Form Attribute Definitions
      # ------------------------------------------------------------------------------
      destinationFormAttributeArray.each { | attribute |
        if vars["options"]["delete"] && !sourceFormAttributeArray.include?(attribute)
            $space_sdk.delete_form_attribute_definition(kapp['slug'],attribute)
        end
      }
    end
  end

  # ------------------------------------------------------------------------------
  # import bridge models
  # *NOTE* - This if the bridge doesn't exist the model will be imported w/ an empty "Bridge Slug" value.
  # ------------------------------------------------------------------------------
  def import_bridge_models(core_path,vars)
    destinationModels = $space_sdk.find_bridge_models()
    destinationModels_Array = (destinationModels.content['models'] || {}).map{ |model| model['name']}

    Dir["#{core_path}/space/models/*.json"].each{ |model|
      body = JSON.parse(File.read(model))
      if destinationModels_Array.include?(body['name'])
        $space_sdk.update_bridge_model(body['name'], body)
      else
        $space_sdk.add_bridge_model(body)
      end
    }
    sourceModelsArray = Dir["#{core_path}/space/models/*.json"].map{ |model| JSON.parse(File.read(model))['name'] }

    destinationModels_Array.each do |model|
      if vars["options"]["delete"] && !sourceModelsArray.include?(model)
        $space_sdk.delete_bridge_model(model)
      end
    end
  end

  def import_kapp_form_data(core_path,kapp)

    promises = []
    Dir["#{core_path}/space/kapps/#{kapp['slug']}/forms/**/submissions*.ndjson"].sort.each { |filename|
      promises << Concurrent::Promise.execute(executor: $pool) do
        begin
          dir = File.dirname(filename)
          form_slug = filename.match(/forms\/(.+)\/submissions\.ndjson/)[1]

          #TODO - Convert to CSV upload path. Disabled until import_submissions_csv signature/body are wired up.
          # convert_json_to_csv(filename)
          # $space_sdk.import_submissions_csv(kapp['slug'], form_slug, body).content

          ## This code could delete all submissions from the form before importing new data
          ## It is commented out because it could be dangerous to have in place and the delete_submission method doesn't exist currently.
          #($space_sdk.find_all_form_submissions(kapp['slug'], form_slug).content['submissions'] || []).each { |submission|
          #  $space_sdk.delete_submission(submission['id'])
          #}

          File.foreach(filename) { |line|
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
            $space_sdk.add_submission(kapp['slug'], form_slug, body).content
          }
        rescue => e
          $mutex.synchronize do
            $logger.error("Failed to import form data from : #{e.message}")
            $logger.error(e.backtrace.join("\n"))
          end
          raise
        end
      end
    }
    promises.each(&:wait!)

    $mutex.synchronize { $logger.info("Finished importing form data for kapp #{kapp['slug']}") }

  end

  # ------------------------------------------------------------------------------
  # Import Space Web APIs
  # ------------------------------------------------------------------------------

  def import_space_web_apis(core_path)
    sourceSpaceWebApisArray = []
    destinationSpaceWebApisArray = ($space_sdk.find_space_webapis().content['webApis'] || {}).map { |definition|  definition['slug']}
    promises = []
    Dir["#{core_path}/space/webApis/*"].each{ |file|
      promises << Concurrent::Promise.execute(executor: $pool) do
        begin
          body = JSON.parse(File.read(file))
          if destinationSpaceWebApisArray.include?(body['slug'])
            $space_sdk.update_space_webapi(body['slug'], body)
          else
            $space_sdk.add_space_webapi(body)
          end
          sourceSpaceWebApisArray.push(body['slug'])
        rescue
        end
      end
    }
    promises.each(&:wait!)
  end
  # ------------------------------------------------------------------------------
  # Migrate Kapp Attribute Definitions
  # ------------------------------------------------------------------------------
  def import_kapp_attribute_definitions(core_path,kapp, vars)
    if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/kappAttributeDefinitions.json")
      sourceKappAttributeArray = []
      destinationKappAttributeArray = ($space_sdk.find_kapp_attribute_definitions(kapp['slug']).content['kappAttributeDefinitions'] || {}).map { |definition|  definition['name']}
      kappAttributeDefinitions = JSON.parse(File.read(file))
      (kappAttributeDefinitions || []).each { |attribute|
          if destinationKappAttributeArray.include?(attribute['name'])
            $space_sdk.update_kapp_attribute_definition(kapp['slug'], attribute['name'], attribute)
          else
            $space_sdk.add_kapp_attribute_definition(kapp['slug'], attribute['name'], attribute['description'], attribute['allowsMultiple'])
          end
          sourceKappAttributeArray.push(attribute['name'])
      }   
      # ------------------------------------------------------------------------------
      # Delete Kapp Attribute Definitions
      # ------------------------------------------------------------------------------
      destinationKappAttributeArray.each { | attribute |
        if vars["options"]["delete"] && !sourceKappAttributeArray.include?(attribute)
            $space_sdk.delete_kapp_attribute_definition(kapp['slug'],attribute)
        end
      }
    end
  end
  # ------------------------------------------------------------------------------
  # Page through find_forms; returns the merged array of form hashes.
  # ------------------------------------------------------------------------------
  def fetch_all_forms(kapp_slug, params={})
    results = []
    params = params.merge('limit' => 1000)
    loop do
      response = $space_sdk.find_forms(kapp_slug, params)
      break unless response.code.to_i == 200
      results.concat(response.content['forms'] || [])
      token = response.content['nextPageToken']
      break if token.nil?
      params['pageToken'] = token
    end
    results
  end

  # ------------------------------------------------------------------------------
  # Page through find_datastore_forms; returns the merged array of form hashes.
  # ------------------------------------------------------------------------------
  def fetch_all_datastore_forms(params={})
    results = []
    params = params.merge('limit' => 1000)
    loop do
      response = $space_sdk.find_datastore_forms(params)
      break unless response.code.to_i == 200
      results.concat(response.content['forms'] || [])
      token = response.content['nextPageToken']
      break if token.nil?
      params['pageToken'] = token
    end
    results
  end

  # ------------------------------------------------------------------------------
  # Import Kapp Forms
  # ------------------------------------------------------------------------------
  def import_forms(core_path,kapp, vars)
    if (forms = Dir["#{core_path}/space/kapps/#{kapp['slug']}/forms/*.json"]).length > 0 
      sourceForms = [] #From import data
      #destinationForms = ($space_sdk.find_forms(kapp['slug']).content['forms'] || {}).map{ |form| form['slug']}
      destinationForms = fetch_all_forms(kapp['slug'], {'export'=>'true'})
      $logger.info ("Iterating kapp forms")
      promises = []


      forms.each do |form_file|
        promises << Concurrent::Promise.execute(executor: $pool) do
          begin
            properties = File.read(form_file)
            form = JSON.parse(properties)
            $mutex.synchronize do
                $logger.info "Currently #{form['slug']}"
                sourceForms.push(form['slug'])
            end

            prev_form = (destinationForms.find { |f| f["slug"] == form['slug'] })
            if !prev_form.nil?
              #Compare old and new forms
              #$space_sdk.compare_forms(destinationForms["#{form['slug']}"], form )
              #Check last updated date/time and compare
              $mutex.synchronize { $logger.info("Comparing previous and current form exports for #{form['slug']}") }
              match = !form['updatedAt'].nil? &&
                      !prev_form['updatedAt'].nil? &&
                      form['updatedAt'] == prev_form['updatedAt']
              #Skip if forms match
              if !match
                $mutex.synchronize { $logger.info("Updating form #{form['slug']}") }
                $space_sdk.update_form(kapp['slug'] ,form['slug'], form)
              else
                $mutex.synchronize { $logger.info("Form #{form['slug']} updatedAt values match, skipping...") }
              end
            else
              $mutex.synchronize { $logger.info("Adding new form #{form['slug']}") }
              $space_sdk.add_form(kapp['slug'], form)
            end
          rescue => e
            $mutex.synchronize do
              $logger.error("Failed to import form from #{form_file}: #{e.class}: #{e.message}")
              $logger.error(e.backtrace.join("\n"))
            end
            raise
          end
        end
      end

      promises.each(&:wait!)

      $mutex.synchronize { $logger.info("Finished importing #{sourceForms.size} forms for kapp #{kapp['slug']}") }

      # ------------------------------------------------------------------------------
      # delete forms
      # ------------------------------------------------------------------------------
      destinationForms.each { |dest_form|
        if vars["options"]["delete"] && !sourceForms.include?(dest_form["slug"])
          #Delete form is disabled
          #$space_sdk.delete_form(kapp['slug'], dest_form["slug"])
        end
      }
    end
  end
  # ------------------------------------------------------------------------------
  # Migrate Kapp Category Definitions
  # ------------------------------------------------------------------------------
  def import_kapp_category_definitions(core_path,kapp,vars)
    if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/categoryAttributeDefinitions.json")
      sourceKappCategoryArray = []
      destinationKappAttributeArray = ($space_sdk.find_category_attribute_definitions(kapp['slug']).content['categoryAttributeDefinitions'] || {}).map { |definition|  definition['name']}  
      kappCategoryDefinitions = JSON.parse(File.read(file))
      (kappCategoryDefinitions || []).each { |attribute|
          if destinationKappAttributeArray.include?(attribute['name'])
            $space_sdk.update_category_attribute_definition(kapp['slug'], attribute['name'], attribute)
          else
            $space_sdk.add_category_attribute_definition(kapp['slug'], attribute['name'], attribute['description'], attribute['allowsMultiple'])
          end
          sourceKappCategoryArray.push(attribute['name'])
      }   
      # ------------------------------------------------------------------------------
      # Delete Kapp Category Definitions
      # ------------------------------------------------------------------------------
      destinationKappAttributeArray.each { | attribute |
        if vars["options"]["delete"] && !sourceKappCategoryArray.include?(attribute)
            $space_sdk.delete_category_attribute_definition(kapp['slug'],attribute)
        end
      }
    end
  end

  def import_kapp_form_type_definitions(core_path, kapp, vars)
    # ------------------------------------------------------------------------------
    # Migrate Kapp Form Type Definitions
    # ------------------------------------------------------------------------------
    if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/formTypes.json")
      sourceFormTypesArray = []
      destinationFormTypesArray = ($space_sdk.find_formtypes(kapp['slug']).content['formTypes'] || {}).map { |formTypes|  formTypes['name']}
      formTypes = JSON.parse(File.read(file))
      (formTypes || []).each { |body|
        if destinationFormTypesArray.include?(body['name'])
          $space_sdk.update_formtype(kapp['slug'], body['name'], body)
        else
          $space_sdk.add_formtype(kapp['slug'], body)
        end
        sourceFormTypesArray.push(body['name'])
      }   
      # ------------------------------------------------------------------------------
      # Delete Kapp Form Type Definitions
      # ------------------------------------------------------------------------------
      destinationFormTypesArray.each { | name |
        if vars["options"]["delete"] && !sourceFormTypesArray.include?(name)
            $space_sdk.delete_formtype(kapp['slug'],name)
        end
      }
    end
  end
  def import_kapp_web_apis(core_path, kapp, vars)
    # ------------------------------------------------------------------------------
    # Add Kapp Web APIs
    # ------------------------------------------------------------------------------
    sourceWebApisArray = []
    destinationWebApisArray = ($space_sdk.find_kapp_webapis(kapp['slug']).content['webApis'] || {}).map { |definition|  definition['slug']}
    Dir["#{core_path}/space/kapps/#{kapp['slug']}/webApis/*"].each { |webApi|
      body = JSON.parse(File.read(webApi))
      if destinationWebApisArray.include?(body['slug'])
        $space_sdk.update_kapp_webapi(kapp['slug'], body['slug'], body)
      else
        $space_sdk.add_kapp_webapi(kapp['slug'], body)
      end
      sourceWebApisArray.push(body['slug'])
    }
    # ------------------------------------------------------------------------------
    # Delete Kapp Web APIs not present in source
    # ------------------------------------------------------------------------------
    destinationWebApisArray.each { |webApi|
      if vars["options"]["delete"] && !sourceWebApisArray.include?(webApi)
        $space_sdk.delete_kapp_webapi(kapp['slug'], webApi)
      end
    }
  end

  def import_kapp_security_policy_definitions(core_path,kapp,vars)
    # ------------------------------------------------------------------------------
    # Migrate Kapp Security Policy Definitions
    # ------------------------------------------------------------------------------
    if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/securityPolicyDefinitions.json")
      sourceSecurtyPolicyArray = []
      destinationSecurtyPolicyArray = ($space_sdk.find_security_policy_definitions(kapp['slug']).content['securityPolicyDefinitions'] || {}).map { |definition|  definition['name']}
      securityPolicyDefinitions = JSON.parse(File.read(file))
      (securityPolicyDefinitions || []).each { |attribute|
          if destinationSecurtyPolicyArray.include?(attribute['name'])
            $space_sdk.update_security_policy_definition(kapp['slug'], attribute['name'], attribute)
          else
            $space_sdk.add_security_policy_definition(kapp['slug'], attribute)
          end
          sourceSecurtyPolicyArray.push(attribute['name'])
      }   

      destinationSecurtyPolicyArray.each { | attribute |
        if vars["options"]["delete"] && !sourceSecurtyPolicyArray.include?(attribute)
            $space_sdk.delete_security_policy_definition(kapp['slug'],attribute)
        end
      }
    end
  end

starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)
import_space()
ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)
elapsed = ending - starting
puts "Time: #{elapsed}"