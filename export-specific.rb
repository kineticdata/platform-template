# RUNNING THE SCRIPT:
#   ruby export-specific.rb -c "<<PATH/CONFIG_FILE.rb>>"
#   ruby export-specific.rb -c "config/foo-web-server.rb"
#
# Example Config File Values 
#
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
  EXPORT:
    space:
      teams: 
        # List Team Names
        # Use "include_membership: true" to export the team membership
        - team_name: <team_name>
          include_membership: true
      attributes:
        space: # List of Space Attributes
          - <space_attribute>
        user:  # List of User Attributes
          - <user_attribute>
        user_profile: # List of User Profile Attributes
          - <user_profile_attribute>
        team: # List of Team Attributes 
           - <team_attribute>
      models: # List of Models
        - <model_name>
    kapps: # List Kapp Slugs
      # For "datastore" logic will determine if form consolidation is used by looking for the "datastore" kapp
      - kapp_slug: datastore 
        forms: # list form slugs
          - form_slug: <form_slug>
            submission: <true/false>
      - kapp_slug: services
        forms: # list form slugs
          - form_slug: <form_slug>
            submission: <true/false>
        categories: # Category Slugs
          - <category_slug>
        attributes: 
            kapp_attributes: # Kapp Attributes
                - <kapp_attribute>
            category_attributes: # Category Attributes
                - <category_attribute>
            form_attributes: # Form Attributes
                - <form_attribute>
    workflow:
      trees: #List of Trees
        # list each using - 'Source :: Source Group :: Name'
        # example: - 'Kinetic Request CE :: Submissions > services > gravel-roads :: Closed'
        - <'Source :: Source Group :: Name'>
      routines: List of Routines
        # list each using - 'Source :: Source Group :: Name'
        # example: - '- :: - :: Name'
        - <'- :: - :: Name'>
      handlers: #List of Handlers
        - <Handler_Definition_Id>
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
require 'optparse'
require 'kinetic_sdk'

template_name = "platform-template"

$logger = Logger.new(STDERR)
$logger.level = Logger::INFO
$logger.formatter = proc do |severity, datetime, progname, msg|
  date_format = datetime.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
  "[#{date_format}] #{severity}: #{msg}\n"
end


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

# determine the directory paths
platform_template_path = File.dirname(File.expand_path(__FILE__))
$core_path = File.join(platform_template_path, "core")
$task_path = File.join(platform_template_path, "task")

# ------------------------------------------------------------------------------
# methods
# ------------------------------------------------------------------------------

def create_valid_filename(filename)
  # Replace all `/` and `\` characters with `-`
  # Replace multiple spaces with single space.
  # Replace all `.` with `/`
  # Replace all `::` with `-` (this ensures nested Teams/Categories maintain a separator)
  # Replace all non-slug characters with ``
  updated_filename = "#{filename.gsub(/(\/)|(\\)/, '-').gsub(/\s{2,}/, ' ').gsub('.', '/').gsub(/::/, '-').gsub(/[^ a-zA-Z0-9_\-\/]/, '')}.json"
end

def export_submissions(item)

  is_datastore = item['kappSlug'] == "datastore" && !$form_consoldidation ? true : false
  $logger.info "Exporting - #{item['kappSlug']} form #{item['formSlug']}"

  # build directory to write files to
  submission_path = is_datastore ?
    "#{$core_path}/space/datastore/forms/#{item['formSlug']}" :
    "#{$core_path}/space/kapps/#{item['kappSlug']}/forms/#{item['formSlug']}"
  
  # get attachment fields from form definition
  attachment_form = is_datastore ?
    $space_sdk.find_datastore_form(item['formSlug'], {"include" => "fields.details"}) :
    $space_sdk.find_form(item['kappSlug'], item['formSlug'], {"include" => "fields.details"})
  # get attachment fields from form definition
  attachement_files = attachment_form.status == 200 ? attachment_form.content['form']['fields'].select{ | file | file['dataType'] == "file" }.map { | field | field['name']  } : {}
  # set base url for attachments
  attachment_base_url = is_datastore ?
    "#{$space_sdk.api_url.gsub("/app/api/v1", "")}/app/datastore" :
    "#{$space_sdk.api_url.gsub("/app/api/v1", "")}"
    
  # create folder to write submission data to
  FileUtils.mkdir_p(submission_path, :mode => 0700)

  # build params to pass to the retrieve_form_submissions method
  params = {"include" => "values", "limit" => 1000, "direction" => "ASC"}

  # open the submissions file in write mode
  file = File.open("#{submission_path}/submissions.ndjson", 'w');

  # ensure the file is empty
  file.truncate(0)
  response = nil
  begin
    # get submissions from datastore form or form

    response = is_datastore ?
      $space_sdk.find_all_form_datastore_submissions(item['formSlug'], params).content :
      $space_sdk.find_form_submissions(item['kappSlug'], item['formSlug'], params).content
    
    if response.has_key?("submissions") && response["submissions"].length > 0
      # iterate over each submission
      (response["submissions"] || []).each do |submission|
        # write each attachment to a a dir
        submission['values'].select{ |field, value| attachement_files.include?(field) && !value.nil?}.each{ |field,value|
          submission_id = submission['id']
          # define the dir to contain the attachment
          download_dir = "#{submission_path}/#{submission_id}/#{field}"
          # evaluate fields with multiple attachments
          value.map.with_index{ | attachment, index |
            # create folder to write attachment
            FileUtils.mkdir_p(download_dir, :mode => 0700)
            # dir and file name to write attachment
            download_path = "#{download_dir}/#{File.join(".", attachment['name'])}"
            # url to retrieve the attachment
            url = URI.escape("#{attachment_base_url}/submissions/#{submission_id}/files/#{field}/#{index}/#{attachment['name']}")
            # retrieve and write attachment
            $space_sdk.stream_download_to_file(download_path, url, {}, $space_sdk.default_headers)
            # add the "path" key to indicate the attachment's location
            attachment['path'] = "/#{submission_id}/#{field}/#{attachment['name']}"
          }
        }
        # append each submission (removing the submission unwanted attributes)
        file.puts(JSON.generate(submission.delete_if { |key, value| REMOVE_DATA_PROPERTIES.member?(key)}))
      end
    end
    params['pageToken'] = response['nextPageToken']
    # get next page of submissions if there are more
  end while !response.nil? && !response['nextPageToken'].nil?
  # close the submissions file
  file.close()
end

# ------------------------------------------------------------------------------
# constants
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# setup
# ------------------------------------------------------------------------------

$logger.info "Installing gems for the \"#{template_name}\" template."
Dir.chdir(platform_template_path) { system("bundle", "install") }

vars = {}

# Read the config file specified in the command line into the variable "vars"
if File.file?(file = "#{platform_template_path}/#{options['CONFIG_FILE']}")
  vars.merge!( YAML.load(File.read(file)) )
end

# Set http_options based on values provided in the config file.
http_options = (vars["http_options"] || {}).each_with_object({}) do |(k,v),result|
  result[k.to_sym] = v
end

# Set variables based on values provided in the config file.
if vars["options"]
  REMOVE_DATA_PROPERTIES = vars["options"]["REMOVE_DATA_PROPERTIES"]
end

# Output the yml file config
$logger.info JSON.pretty_generate(vars)

# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------

$logger.info "Removing files and folders from the existing \"#{template_name}\" template."
FileUtils.rm_rf Dir.glob("#{$core_path}/*")

$logger.info "Setting up the Core SDK"
 
$space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server_url"],
  space_slug: vars["core"]["space_slug"],
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{$core_path}" })
})

# fetch export from core service and write to export directory
$logger.info "Exporting the core components."
$logger.info "  exporting with api: #{$space_sdk.api_url}"
$logger.info "   - exporting configuration data (Kapps,forms, etc)"

# Determine if environment has form consolidation
$form_consoldidation = $space_sdk.get("#{vars["core"]["server_url"]}/app/api/v1/version").content["version"]["version"].to_f > 5.0

# ------------------------------------------------------------------------------
# Space
# ------------------------------------------------------------------------------
if vars['options'] && vars['options']['EXPORT'] && vars['options']['EXPORT']['space']
  
  # Export Teams
  $logger.info "Exporting \"Teams\" for space"
  (vars['options']['EXPORT']['space']['teams'] || []).each{ |team|
    if team['team_name']
      $logger.info "Exporting  \"#{team} Team\" for space"  
      base_filename = create_valid_filename(team["team_name"])
      export = $space_sdk.find_team(team["team_name"], {"include":"details,attributes,#{"memberships" if team["include_membership"]}"})
      $space_sdk.write_object_to_file("#{$core_path}/space/teams/#{base_filename}.json", export.content["team"]) if export.status == 200
    end
  }

  # Export Space Attributes
  if vars['options']['EXPORT']['space']['attributes']
    
    # Export User Attributes
    $logger.info "Exporting \"User Attributes\" for space"    
    attributes_array = []
    (vars['options']['EXPORT']['space']['attributes']['user'] || []).compact.each{ | attribute |
      export = $space_sdk.find_user_attribute_definition(attribute)
      attributes_array << export.content["userAttributeDefinition"] if export.status == 200
    }    
    $space_sdk.write_object_to_file("#{$core_path}/space/userAttributeDefinitions.json", attributes_array) unless attributes_array.length == 0
    
    # Export User Attributes
    $logger.info "Exporting \"User Profile Attributes\" for space"    
    attributes_array = []
    (vars['options']['EXPORT']['space']['attributes']['user_profile'] || []).compact.each{ | attribute |
      export = $space_sdk.find_user_profile_attribute_definition(attribute)
      attributes_array << export.content["userProfileAttributeDefinitions"] if export.status == 200
    }       
    $space_sdk.write_object_to_file("#{$core_path}/space/userProfileAttributeDefinitions.json", attributes_array) unless attributes_array.length == 0
    
    # Export Team Attributes
    $logger.info "Exporting \"Team Attributes\" for space"    
    attributes_array = []
    (vars['options']['EXPORT']['space']['attributes']['team'] || []).compact.each{ | attribute |
      export = $space_sdk.find_team_attribute_definition(attribute)
      attributes_array << export.content["teamAttributeDefinition"] if export.status == 200
    }    
    $space_sdk.write_object_to_file("#{$core_path}/space/teamAttributeDefinitions.json", attributes_array) unless attributes_array.length == 0
    
    # Export Space Attributes
    $logger.info "Exporting \"Space Attributes\" for space"    
    attributes_array = []
    (vars['options']['EXPORT']['space']['attributes']['space'] || []).compact.each{ | attribute |
      export = $space_sdk.find_space_attribute_definition(attribute)
      attributes_array << export.content["spaceAttributeDefinition"] if export.status == 200
    }    
    $space_sdk.write_object_to_file("#{$core_path}/space/spaceAttributeDefinitions.json", attributes_array) unless attributes_array.length == 0
    
    # Export Models
    $logger.info "Exporting \"Models\" for space"    
    (vars['options']['EXPORT']['space']['models'] || []).compact.each{ | model |
      export = $space_sdk.find_bridge_model(model)
      base_filename = create_valid_filename(model)
      $space_sdk.write_object_to_file("#{$core_path}/space/models/#{base_filename}.json", export.content["model"]) if export.status == 200
    }    
      
  end
end 

# ------------------------------------------------------------------------------
# Kapps
# ------------------------------------------------------------------------------
if vars['options'] && vars['options']['EXPORT'] && vars['options']['EXPORT']['kapps']
  # Make kapps dir
  kapps_path = "#{$core_path}/space/kapps"

  # Iterate through the forms in each kapps
  (vars['options']['EXPORT']['kapps'] || []).each{ |kapp|
    $logger.info "Exporting the \"#{kapp['kapp_slug']}\" Kapp"
    kapp_path = "#{kapps_path}/#{kapp['kapp_slug']}"
    forms_path = kapp['kapp_slug'] == "datastore" ? !$form_consoldidation ? "#{$core_path}/space/datastore" : "#{kapp_path}/forms" : "#{kapp_path}/forms" # set dir path
    
    # Iterate through each form
    (kapp['forms'] || [] ).each { |form|
      if form['form_slug']
        export = $space_sdk.export_form(kapp['kapp_slug'], form['form_slug']) # Export the form
        $space_sdk.write_object_to_file("#{forms_path}/#{form['form_slug']}.json", export.content['form']) if export.status == 200
        # Export Submissions
$logger.info "######################{form}"
        if form['submissions'] && form['submissions'] == true 
          export_obj = {"kappSlug"=>kapp['kapp_slug'],"formSlug"=>form['form_slug']}
          export_submissions(export_obj) # Export Submissions
        end
      end
    }

    $logger.info "Exporting \"Attributes\" for the #{kapp['kapp_slug']} kapp"
    if kapp['attributes']
      
      # Export Kapp Attributes
      $logger.info "Exporting \"Kapp Attributes\" for the #{kapp['kapp_slug']} kapp"    
      attributes_array = []
      (kapp['attributes']['kapp_attributes'] || []).compact.each{ | kapp_attribute |
        export = $space_sdk.find_kapp_attribute_definition(kapp['kapp_slug'], kapp_attribute)
        attributes_array << export.content['kappAttributeDefinition']
      }    
      $space_sdk.write_object_to_file("#{kapp_path}/kappAttributeDefinitions.json", attributes_array) unless attributes_array.length == 0
      
      # Export Category Attributes
      $logger.info "Exporting \"Category Attributes\" for the #{kapp['kapp_slug']} kapp"    
      attributes_array = []
      (kapp['attributes']['category_attributes'] || []).compact.each{ | category_attribute |
        export = $space_sdk.find_category_attribute_definition(kapp['kapp_slug'], category_attribute)
        attributes_array << export.content['categoryAttributeDefinition']
      }    
      $space_sdk.write_object_to_file("#{kapp_path}/categoryAttributeDefinitions.json", attributes_array) unless attributes_array.length == 0
      
      # Export Form Attributes
      $logger.info "Exporting \"Form Attributes\" for the #{kapp['kapp_slug']} kapp"    
      attributes_array = []
      (kapp['attributes']['form_attributes'] || []).compact.each{ | form_attribute |
        export = $space_sdk.find_form_attribute_definition(kapp['kapp_slug'], form_attribute)
        attributes_array << export.content['formAttributeDefinition']
      }    
      $space_sdk.write_object_to_file("#{kapp_path}/formAttributeDefinitions.json", attributes_array) unless attributes_array.length == 0
    end
    
    # Export Kapp Categories
    $logger.info "Exporting \"Categories\" for the #{kapp['kapp_slug']} kapp"    
    categories_array = []
    (kapp['categories'] || []).compact.each{ | category_slug |
      export = $space_sdk.find_category_on_kapp(kapp['kapp_slug'], category_slug, {"include":"attributes"})
      categories_array << export.content['category']
    }    
    $space_sdk.write_object_to_file("#{kapp_path}/categories.json", categories_array) unless categories_array.length == 0

    # Export WebAPIs
    $logger.info "Exporting \"WebAPIs\" for the #{kapp['kapp_slug']} kapp"    
    webapis_array = []
    (kapp['webapis'] || []).compact.each{ | webapi_slug |
      $logger.info (kapp['kapp_slug'])
      export = $space_sdk.find_kapp_webapi(kapp['kapp_slug'], webapi_slug, {"include":"securityPolicies"})
      $logger.info export.content
      webapis_array << export.content['webApi']
    }    
    $space_sdk.write_object_to_file("#{kapp_path}/webapis.json", webapis_array) unless webapis_array.length == 0

	# Export Security Policies
    $logger.info "Exporting \"Security Policies\" for the #{kapp['kapp_slug']} kapp"    
    securitypolicy_array = []
    (kapp['securitypolicy'] || []).compact.each{ | name |
      $logger.info (kapp['kapp_slug']) 
      export = $space_sdk.find_security_policy_definition(kapp['kapp_slug'], name)
      securitypolicy_array << export.content['securityPolicyDefinition']
    }    
    $space_sdk.write_object_to_file("#{kapp_path}/securitypolicy.json", securitypolicy_array) unless securitypolicy_array.length == 0
  }
  
end

# ------------------------------------------------------------------------------
# task
# ------------------------------------------------------------------------------
$logger.info "Removing files and folders from the existing \"#{template_name}\" template."
FileUtils.rm_rf Dir.glob("#{$task_path}/*")

$logger.info "Setting up the Task SDK"

task_sdk = KineticSdk::Task.new({
  app_server_url: "#{vars["task"]["server_url"]}",
  username: vars["task"]["service_user_username"],
  password: vars["task"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{$task_path}" })
})

if vars['options'] && vars['options']['EXPORT'] && vars['options']['EXPORT']['workflow']
  # Export Trees
  (vars['options']['EXPORT']['workflow']['trees'] || []).compact.each{ |tree_name|
      tree = task_sdk.export_tree(tree_name)
  }

  # Export Routines
  (vars['options']['EXPORT']['workflow']['routines'] || []).compact.each{ |routine_name|
      tree = task_sdk.export_tree(routine_name) if task_sdk.find_tree(routine_name).status == 200
  }  

  # Export Handlers
  (vars['options']['EXPORT']['workflow']['handlers'] || []).compact.each{ |handler_id|
      handler = task_sdk.export_handler(handler_id) if task_sdk.find_handler(handler_id).status == 200
  } 
end

$logger.info "Finished exporting"

