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

require 'logger'      #For System Logging
require 'json'
require 'optparse'    #For argument parsing
require 'kinetic_sdk' 
require 'Find'        #For config list building
require 'io/console'  #For password request
require 'base64'      #For pwd encoding

template_name = "platform-template"
$pwdFields = ["core","task"]

logger = Logger.new(STDERR)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  date_format = datetime.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
  "[#{date_format}] #{severity}: #{msg}\n"
end



# Determine the Present Working Directory
pwd = File.expand_path(File.dirname(__FILE__))


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


#Configuration Selection
def config_selection(config_folder_path, logger)

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
  #Check config folder for yaml/yml files containing the word 'export'
  begin
    Find.find("#{config_folder_path}/") do |file|
      configArray.append(File.basename(file)) if config_exts.include?(File.extname(file)) && (File.basename(file).include?('export'))
    end
  rescue error
    #No config files found in config folder
    logger.error "Error finding default config file path!"
    logger.error "Error reported: #{error}"
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
      logger.info "Error selecting config file! Exiting..."
      puts "Error selecting config file!"
      puts "Exiting..."
      gets
      exit
    end
  end while true
  return configFile
end


#End method

# determine the directory paths
platform_template_path = File.dirname(File.expand_path(__FILE__))
config_folder_path = File.join(platform_template_path,'config')

if options["CONFIG_FILE"].nil?
  options["CONFIG_FILE"] = config_selection(config_folder_path, logger)
end

# ------------------------------------------------------------------------------
# methods
# ------------------------------------------------------------------------------

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
file = "#{platform_template_path}/#{options['CONFIG_FILE']}"

# Check if configuration file exists
logger.info "Validating configuration file."
begin
  if File.exist?(file) != true
    file = "#{config_folder_path}/#{options['CONFIG_FILE']}"
    if File.exist?(file) != true
      raise "The file \"#{options['CONFIG_FILE']}\" does not exist in the base or config directories."
    end
  end
rescue => error
  logger.info error
  logger.info "Exiting..."
  exit
end

# Read the config file specified in the command line into the variable "vars"
begin
  vars.merge!( YAML.load(File.read(file)) )
rescue => error
  logger.info "Error loading YAML configuration"
  logger.info error
  logger.info "Exiting..."
  gets
  exit
end
logger.info "Configuration file passed validation."


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
    logger.error("There was an error while updating variables file:")
    logger.error(ArgumentError)
  ensure
    fileObj.close
  end
end

#Decode password to utilize
def DecodePWD(file, vars, pwdLoc)
  pwdAttribute = vars[pwdLoc]["service_user_password"]
  # if !pwdAttribute.is_a?(String) || Base64.strict_encode64(Base64.decode64(pwdAttribute)) != pwdAttribute || pwdAttribute === "<PASSWORD>"
  #   puts "Adjusting password for #{pwdLoc}"
  #   SecurePWD(file, vars, pwdLoc)
  #   pwdAttribute = vars[pwdLoc]["service_user_password"]
  # end
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

#OLD
#Setup secure pwd function - If entry is not a string(nil) or unencoded, then run pwd encoder/prompt
# if !vars["core"]["service_user_password"].is_a?(String) || Base64.strict_encode64(Base64.decode64(vars["core"]["service_user_password"])) != vars["core"]["service_user_password"]
#   SecurePWD(file,vars,"core")
#   logger.info("Core pwd encoded")
# end
# if !vars["task"]["service_user_password"].is_a?(String) || Base64.strict_encode64(Base64.decode64(vars["task"]["service_user_password"])) != vars["task"]["service_user_password"]
#   SecurePWD(file,vars,"task")
#   logger.info("Task pwd encoded")
# end
#Write PT pwds into local variable
# vars["core"]["service_user_password"] = Base64.decode64(vars["core"]["service_user_password"])
# vars["task"]["service_user_password"] = Base64.decode64(vars["task"]["service_user_password"])

#NEW
#Will confirm there is a valid, encoded password and decode. Otherwise it will prompt/encode pwd and return decoded variant

#Temporary workaround - run decode and trash first time to ensure improper data written - Otherwise first action will store decoded var and 2nd will write it to the config
ValidatePWD(file, vars)
#TODO - Review whether or not vars is handed in or just the pwd value
vars["core"]["service_user_password"] = DecodePWD(file, vars, "core")
vars["task"]["service_user_password"] = DecodePWD(file, vars, "task")
puts "Pause here..."
gets
exit

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

# Set variables based on values provided in the config file.
SUBMISSIONS_TO_EXPORT = vars["options"]["SUBMISSIONS_TO_EXPORT"]
REMOVE_DATA_PROPERTIES = vars["options"]["REMOVE_DATA_PROPERTIES"]

#Config exports folder exists, if not then create
if !File.directory?(File.join(platform_template_path,"exports"))
  Dir.mkdir(File.join(platform_template_path, "exports"))
end

#Setting core paths utilzing variables
if !vars['core']['space_slug'].nil?
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
logger.info "Output of Configuration File: \r #{JSON.pretty_generate(vars)}"

logger.info "Setting up the SDK"
 
space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server_url"],
  space_slug: vars["core"]["space_slug"],
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{core_path}" })
})

task_sdk = KineticSdk::Task.new({
  app_server_url: "#{vars["task"]["server_url"]}",
  username: vars["task"]["service_user_username"],
  password: vars["task"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{task_path}" })
})

# ------------------------------------------------------------------------------
# Validate connection and Credentials to Server
# ------------------------------------------------------------------------------

# Validate Core Connection
begin
  logger.info "Validating connection to Core \"#{space_sdk.api_url}\""
  response = space_sdk.me()
  if response.status == 0
      raise response.message
  elsif response.status.to_s.match(/4\d{2}/)
    raise response.content['error']
  end
rescue => error
  logger.info error
  exit
end

# Validate Task Connection
begin
  logger.info "Validating connection to Task \"#{task_sdk.api_url}\""
  response = task_sdk.environment()
  if response.status == 0
    raise response.message
  elsif response.status.to_s.match(/4\d{2}/)
    raise response.content['error']
  end
rescue => error
  logger.info error
  exit
end

logger.info "Validating connection to Cors and Task was Successful"

# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------


logger.info "Removing files and folders from the existing \"#{template_name}\" template."
FileUtils.rm_rf Dir.glob("#{core_path}/*")

logger.info "Setting up the Core SDK"

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
            url = "#{attachment_base_url}/submissions/#{submission_id}/files/#{ERB::Util.url_encode(field)}/#{index}/#{ERB::Util.url_encode(attachment['name'])}"
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

# ------------------------------------------------------------------------------
# complete
# ------------------------------------------------------------------------------

logger.info "Finished exporting the \"#{template_name}\" template."
