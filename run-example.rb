require "json"

space_name = "Your Space Name Here"
space_slug = "your-space-slug-here"
server = "https://#{space_slug}.kinops.io"
username = "username for the space"
password = "password for the space"

data = {
  "core" => {
    "api" => "#{server}/app/api/v1",
    "agent_api" => "#{server}/app/components/agent/app/api/v1",
    "proxy_url" => "#{server}/app/components",
    "server" => server,
    "space_slug" => space_slug,
    "space_name" => space_name,
    "service_user_username" => username,
    "service_user_password" => password,
    "task_api_v1" => "#{server}/app/components/task/app/api/v1",
    "task_api_v2" => "#{server}/app/components/task/app/api/v2",
  },
  "http_options" => {
    "log_level" => "info",
    "log_output" => "stderr",
  },
}

puts "Exporting #{space_slug}"
`ruby export.rb #{data.to_json.inspect}`
