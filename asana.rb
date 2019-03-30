#!/usr/bin/env ruby

require "json"
require "net/https"
require "yaml"


module Asana
  def Asana.init
    begin
      @@config = YAML.load_file File.expand_path "~/.asana-client"
      @user_id = @@config['user_id']
      @workspace_id = @@config['workspace_id']
      # puts "User: #{@user_id} Worskpace: #{@workspace_id}"
    rescue
      abort "Config error: ~/.asana-client.\nSee https://github.com/richgong/asana-ruby-script for instructions."
    end
  end

  def Asana.parse(args)
    if args.empty?
      tasks = Asana.get "tasks?workspace=#{@workspace_id}&assignee=me&completed_since=now"
      show = false # TODO: set to true here, if you want to show everything
      tasks["data"].each do |task|
        show = true if task['name'].end_with?('now:')
        puts "#{task['id'].to_s.rjust(20)}) #{task['name']}" if show
      end
      exit
    end

    cmd = args.shift
    value = args.join ' '

    case cmd
    when 'd'
      if value =~ /^(\d+)$/
        Asana.put "tasks/#{$1}", { "completed" => true }
        puts "Task completed!"
      else
        puts "Missing task ID"
      end
    when 'p'
      projects = Asana.get "projects?workspace=#{@workspace_id}&archived=false"
      projects["data"].each do |project|
        puts project['name']
      end
    when 'n'
      result = Asana.post "tasks", {
          "workspace" => @workspace_id,
          "name" => value,
          "assignee" => 'me',
      }
      # add task to project
      # Asana.post "tasks/#{task['data']['id']}/addProject", { "project" => project.id }
      puts "New task: https://app.asana.com/0/0/#{result['data']['id']}"
    else
      abort "Unknown command: #{cmd}"
    end
  end

  def Asana.get(url)
    return Asana.http_request(Net::HTTP::Get, url, nil, nil)
  end

  def Asana.put(url, data, query = nil)
    return Asana.http_request(Net::HTTP::Put, url, data, query)
  end

  def Asana.post(url, data, query = nil)
    return Asana.http_request(Net::HTTP::Post, url, data, query)
  end

  def Asana.http_request(type, url, data, query)
    uri = URI.parse "https://app.asana.com/api/1.0/#{url}"
    puts "s) #{uri}"
    http = Net::HTTP.new uri.host, uri.port
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    header = {
        "Content-Type" => "application/json"
    }
    req = type.new("#{uri.path}?#{uri.query}", header)
    req.basic_auth @@config["api_key"], ''
    if req.respond_to?(:set_form_data) && !data.nil?
      req.set_form_data data
    end
    res = http.start { |http| http.request req  }
    return JSON.parse(res.body)
  end
end


if __FILE__ == $0
  Asana.init
  Asana.parse ARGV
end
