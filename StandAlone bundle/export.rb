# RUNNING THE SCRIPT:
#   ruby export.rb -c "<<PATH/CONFIG_FILE.rb>>"
#   ruby export.rb -c "config/foo-web-server.rb"
#
# Example Config File Values (See Readme for additional details)
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
    SUBMISSIONS_TO_EXPORT:
    - datastore: true
      formSlug: <FORM_SLUG>

    REMOVE_DATA_PROPERTIES:
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
  task:
    # server_url: https://<SPACE>.kinops.io/app/components/task   OR https://<SERVER_NAME>.com/kinetic-task
    server_url: https://web-server.com
    service_user_username: <USER_NAME>
    service_user_password: <PASSWORD>
  http_options:
    log_level: info
    log_output: stderr

=end


#Export_Command ocra export.rb --no-dep-run --add-all-core --gem-files C:\Ruby32-x64\bin\ruby_builtin_dlls --gem-scripts C:\Ruby32-x64\lib\ruby\gems\3.2.0\gems\kinetic_sdk-5.0.21 --gemfile ../Gemfile
require 'logger'
require 'json'
require 'optparse'
require 'kinetic_sdk'
require 'Find'
require 'rexml'

template_name = "platform-template"
# pwd = File.expand_path(File.dirname(__FILE__))
# pwd = File.path('C:\Users\travis.wiese\Source\repos\platform-template\StandAlone bundle')
pwd =  Dir.pwd
# logger = Logger.new(STDERR)
begin
  logger = Logger.new("#{pwd}\\output.log")
rescue
  logger = Logger.new('C:\temp\KD_export_output.log')
  #TODO - Ask for path of configs
end
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  date_format = datetime.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
  "[#{date_format}] #{severity}: #{msg}\n"
end

logger.info "Base directory: #{pwd}"
# Determine the Present Working Directory
configFile = nil

ARGV << '-h' if ARGV.empty?
# The options specified on the command line will be collected in *options*.
options = {}
OptionParser.new do |opts|
  break if opts === nil
  opts.on("-c", "--c CONFIG_FILE", "The Configuration file to use") do |config|
    configFile = config
  end

end.parse!


# determine the directory paths
  # platform_template_path = File.dirname(File.expand_path(__FILE__))
  platform_template_path = Dir.pwd
  config_folder_path = File.join(platform_template_path,'config')

  #If no config passed through, run config selector
if configFile == nil
  configFile = config_selection
end
puts "config: #{configFile}"

  logger.info "Post selection"

# ------------------------------------------------------------------------------
# methods
# ------------------------------------------------------------------------------

#Selection method if not passing config file path
def config_selection

  

  #Ensure config folder exists
  if !File.directory?(config_folder_path)
    logger.info "Config folder not found at #{config_folder_path}"
    puts "Cannot find config folder!"
    puts "Exiting..."
    gets
    exit
  end

  # #Determine Config file to use
  config_exts = ['.yaml','.yml']
  configArray = []
  logger.info "Checking #{config_folder_path} for config files"
  begin
    Find.find("#{config_folder_path}/") do |file|
      configArray.append(File.basename(file)) if config_exts.include?(File.extname(file)) && (File.basename(file).include?('export'))
    end
  rescue
    #No config files found in config folder
    logger.info "Error finding default config file path!"
    puts "Cannot find config files in default path! (#{pwd})"
    puts "Exiting script..."
    gets
    exit
  end
  logger.info "Found config files"



  #Print config file options with number indicators to select
  puts "Select your config file"
  configArray.each_with_index do |cFile, index|
    puts "#{index+1}) #{cFile}" 
  end
  logger.info "Select section"
  begin
    print "Selection (0 to repeat options): "
    sel = gets.chomp.to_i
    begin
      puts "sel is #{sel}"
      if sel === 0
        configArray.each_with_index do |cFile, index|
          puts "#{index+1}) #{cFile}" 
        end
        next
      end
      configFile = configArray[sel-1]
      logger.info "Option #{sel} - #{configFile}"
      break
    rescue
      logger.info "Error selecting config file!"
      puts "Error selecting config file!"
      puts "Exiting..."
      gets
      exit
    end
  end while true
  return configFile
end

# Removes discussion id attribute from a given model
def remove_discussion_id_attribute(model)
  if !model.is_a?(Array)
    if model.has_key?("attributes")
      scrubbed = model["attributes"].select do |attribute|
        attribute["name"] != "Discussion Id"
      end
    end
    model["attributes"] = scrubbed
  end
  return model
end

# ------------------------------------------------------------------------------
# constants
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# setup
# ------------------------------------------------------------------------------

logger.info "Installing gems for the \"#{template_name}\" template."
Dir.chdir(platform_template_path) { system("bundle", "install") }

vars = {}

# Read the config file specified from the above selection

if File.file?(file = "#{config_folder_path}/#{configFile}")
  vars.merge!( YAML.load(File.read(file)) )
end

# Set http_options based on values provided in the config file.
http_options = (vars["http_options"] || {}).each_with_object({}) do |(k,v),result|
  result[k.to_sym] = v
end

# Set variables based on values provided in the config file.
SUBMISSIONS_TO_EXPORT = vars["options"]["SUBMISSIONS_TO_EXPORT"]
REMOVE_DATA_PROPERTIES = vars["options"]["REMOVE_DATA_PROPERTIES"]

# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------

#Setting core paths
core_path = File.join(platform_template_path, "exports", vars['core']['space_slug'], "core")
task_path = File.join(platform_template_path, "exports", vars['core']['space_slug'], "task")

logger.info "Setting up the Core SDK"
  
space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server_url"],
  space_slug: vars["core"]["space_slug"],
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{core_path}" })
})



logger.info "Removing files and folders from the existing \"#{template_name}\" template."
FileUtils.rm_rf Dir.glob("#{core_path}/*")

# fetch export from core service and write to export directory
logger.info "Exporting the core components for the \"#{template_name}\" template."
logger.info "  exporting with api: #{space_sdk.api_url}"
logger.info "   - exporting configuration data (Kapps,forms, etc)"
space_sdk.export_space

# cleanup properties that should not be committed with export
# bridge keys
Dir["#{core_path}/space/bridges/*.json"].each do |filename|
  bridge = JSON.parse(File.read(filename))
  if bridge.has_key?("key")
    bridge.delete("key")
    File.open(filename, 'w') { |file| file.write(JSON.pretty_generate(bridge)) }
  end
end

# cleanup space
filename = "#{core_path}/space.json"
space = JSON.parse(File.read(filename))
# filestore key
if space.has_key?("filestore") && space["filestore"].has_key?("key")
  space["filestore"].delete("key")
end
# platform components
if space.has_key?("platformComponents")
  if space["platformComponents"].has_key?("task")
    space["platformComponents"].delete("task")
  end 
  (space["platformComponents"]["agents"] || []).each_with_index do |agent,idx|
    space["platformComponents"]["agents"][idx]["url"] = ""
  end
end
# rewrite the space file
File.open(filename, 'w') { |file| file.write(JSON.pretty_generate(space)) }

# cleanup discussion ids
Dir["#{core_path}/**/*.json"].each do |filename|
  model = remove_discussion_id_attribute(JSON.parse(File.read(filename)))
  File.open(filename, 'w') { |file| file.write(JSON.pretty_generate(model)) }
end

# export submissions
logger.info "Exporting and writing submission data"
(SUBMISSIONS_TO_EXPORT || []).delete_if{ |item| item["kappSlug"].nil?}.each do |item|
  is_datastore = item["datastore"] || false
  logger.info "Exporting - #{is_datastore ? 'datastore' : 'kapp'} form #{item['formSlug']}"
  # build directory to write files to
  submission_path = is_datastore ?
    "#{core_path}/space/datastore/forms/#{item['formSlug']}" :
    "#{core_path}/space/kapps/#{item['kappSlug']}/forms/#{item['formSlug']}"
  
  # get attachment fields from form definition
  attachment_form = is_datastore ?
    space_sdk.find_datastore_form(item['formSlug'], {"include" => "fields.details"}) :
    space_sdk.find_form(item['kappSlug'], item['formSlug'], {"include" => "fields.details"})
  
  # get attachment fields from form definition
  attachement_files = attachment_form.status == 200 ? attachment_form.content['form']['fields'].select{ | file | file['dataType'] == "file" }.map { | field | field['name']  } : {}
  
  # set base url for attachments
  attachment_base_url = is_datastore ?
    "#{space_sdk.api_url.gsub("/app/api/v1", "")}/app/datastore" :
    "#{space_sdk.api_url.gsub("/app/api/v1", "")}"
    
  # create folder to write submission data to
  FileUtils.mkdir_p(submission_path, :mode => 0700)

  # build params to pass to the retrieve_form_submissions method
  params = {"include" => "details,children,origin,parent,values", "limit" => 1000, "direction" => "ASC"}

  # open the submissions file in write mode
  file = File.open("#{submission_path}/submissions.ndjson", 'w');

  # ensure the file is empty
  file.truncate(0)
  response = nil
  begin
    # get submissions from datastore form or form
    response = is_datastore ?
      space_sdk.find_all_form_datastore_submissions(item['formSlug'], params).content :
      space_sdk.find_form_submissions(item['kappSlug'], item['formSlug'], params).content
    if response.has_key?("submissions")
      # iterate over each submission
      (response["submissions"] || []).each do |submission|
        # write each attachment to a a dir
        submission['values'].select{ |field, value| attachement_files.include?(field)}.each{ |field,value|
          submission_id = submission['id']
          # define the dir to contain the attahment
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
            space_sdk.stream_download_to_file(download_path, url, {}, space_sdk.default_headers)
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
logger.info "  - submission data export complete"

# ------------------------------------------------------------------------------
# task
# ------------------------------------------------------------------------------


task_sdk = KineticSdk::Task.new({
  app_server_url: "#{vars["task"]["server_url"]}",
  username: vars["task"]["service_user_username"],
  password: vars["task"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{task_path}" })
})


logger.info "Removing files and folders from the existing \"#{template_name}\" template."
FileUtils.rm_rf Dir.glob("#{task_path}/*")

logger.info "Exporting the task components for the \"#{template_name}\" template."
logger.info "  exporting with api: #{task_sdk.api_url}"

# export all sources, trees, routines, handlers,
# groups, policy rules, categories, and access keys
task_sdk.export_sources()
task_sdk.find_sources().content['sourceRoots'].each do |source|
  task_sdk.find_trees({ "source" => source['name'] }).content['trees'].each do |tree|
    task_sdk.export_tree(tree['title'])
  end
end
task_sdk.export_routines()
task_sdk.export_handlers()
task_sdk.export_groups()
task_sdk.export_policy_rules()
task_sdk.export_categories()
task_sdk.export_access_keys()

# Export workflows as these are not the same as Trees and Routines
space_sdk.export_workflows()

# ------------------------------------------------------------------------------
# complete
# ------------------------------------------------------------------------------

logger.info "Finished exporting the \"#{template_name}\" template."
