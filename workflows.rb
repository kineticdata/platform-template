require 'fileutils'
require 'pp'

def import_workflows(core_path, core_sdk)
  space_re = /workflows\/(.+)\/.+\.json/
  kapp_re = /kapps\/([a-z0-9\-]+)\/workflows\/(.+)\/.+\.json/
  form_re = /kapps\/([a-z0-9\-]+)\/forms\/workflows\/([a-z0-9\-]+)\/(.+)\/.+\.json/

  # import space workflows
  Dir["#{core_path}/space/workflows/**/*.json"].each do |filename|
    if filename.match?(space_re)
      event = decode_event(filename.match(space_re)[1])
      payload = workflow_payload(filename, event)
      res = core_sdk.add_space_workflow(payload)
    end
  end

  # import kapp / form workflows
  Dir["#{core_path}/space/kapps/**/workflows/**/*.json"].each do |filename|
    if filename.match?(kapp_re)
      kapp_slug = filename.match(kapp_re)[1]
      event = decode_event(filename.match(kapp_re)[2])
      payload = workflow_payload(filename, event)
      res = core_sdk.add_kapp_workflow(kapp_slug, payload)
    elsif filename.match?(form_re)
      kapp_slug = filename.match(form_re)[1]
      form_slug = filename.match(form_re)[2]
      event = decode_event(filename.match(form_re)[3])
      payload = workflow_payload(filename, event)
      res = core_sdk.add_form_workflow(kapp_slug, form_slug, payload)
    end
  end
end


def export_workflows(core_path, core_sdk, task_sdk)
  # space workflows
  res = core_sdk.find_space_workflows
  if res.status == 200
    space_wf_path = "#{core_path}/space/workflows"
    res.content["workflows"].each do |workflow|
      # a workflow will have an event value, regular trees / routines do not
      unless workflow["event"].nil?
        # retrieve the workflow tree json
        res = core_sdk.find_space_workflow(workflow["id"])
        if res.status == 200
            write_workflow_file(space_wf_path, workflow, res.content["treeJson"])
        else
            raise "(#{res.code}) Error retrieving space workflow tree: #{res.message}"
        end
      end
    end
  else
    raise "(#{res.code}) Error retrieving space workflows: #{res.message}"
  end

  # kapp / form workflows
  kapps_path = "#{core_path}/space/kapps"
  Dir.children(kapps_path).keep_if{ |f| File.directory?("#{kapps_path}/#{f}") }.each do |kapp_slug|
    res = core_sdk.find_kapp_workflows(kapp_slug)
    if res.status == 200
      kapp_wf_path = "#{kapps_path}/#{kapp_slug}/workflows"
      res.content["workflows"].each do |workflow|
        # a workflow will have an event value, regular trees / routines do not
        unless workflow["event"].nil?        
            # retrieve the workflow tree json
            res = core_sdk.find_kapp_workflow(kapp_slug, workflow["id"])
            if res.status == 200
            write_workflow_file(kapp_wf_path, workflow, res.content["treeJson"])
            else
            raise "(#{res.code}) Error retrieving kapp workflow tree: #{res.message}"
            end
        end
      end
    else
      raise "(#{res.code}) Error retrieving kapp workflows: #{res.message}"
    end

    forms_path = "#{kapps_path}/#{kapp_slug}/forms"

    (File.directory?(forms_path ) && Dir.children(forms_path).keep_if{ |f| File.extname("#{forms_path}/#{f}") == ".json"  }|| []).each do |form_file|
      form_content = JSON.parse(File.read("#{forms_path}/#{form_file}"))
      form_slug = form_content["slug"]
      res = core_sdk.find_form_workflows(kapp_slug, form_slug)
      if res.status == 200
        form_wf_path = "#{forms_path}/workflows/#{form_slug}"
        res.content["workflows"].each do |workflow|
            # a workflow will have an event value, regular trees / routines do not
            unless workflow["event"].nil?
                # retrieve the workflow tree json
                res = core_sdk.find_form_workflow(kapp_slug, form_slug, workflow["id"])
                if res.status == 200
                    write_workflow_file(form_wf_path, workflow, res.content["treeJson"])
                else
                    raise "(#{res.code}) Error retrieving form workflow tree: #{res.message}"
                end
            end
        end
      else
        raise "(#{res.code}) Error retrieving form workflows: #{res.message}"
      end
    end
  end
end


def workflow_payload(filename, event)
  tree = JSON.parse(File.read(filename))
  name = tree["name"]

  {
    "event" => event,
    "name" => name,
    "treeJson" => tree
  }
end


def write_workflow_file(workflows_path, workflow_summary, tree_json)
  id = workflow_summary["id"]
  event = !workflow_summary["event"].nil? ? encode_event(workflow_summary["event"]) : nil
  name = tree_json["name"]

  event_path = "#{workflows_path}/#{event}"
  file_name = name.split(" ").map{ |s| s.downcase }.join(".")    + ".json"

  FileUtils.mkdir_p(event_path)
  File.write("#{event_path}/#{file_name}", JSON.pretty_generate(tree_json))
end


def decode_event(evt)
  evt.split(".").map{ |s| s.capitalize }.join(" ")
end


def encode_event(evt)
  evt.split(" ").map{ |s| s.downcase }.join(".")
end
