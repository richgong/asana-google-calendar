#!/usr/bin/env ruby

require "json"
require "net/https"
require "yaml"


module Asana
  CONFIG_FILE = File.expand_path '~/.asana-client'
  def self.init
    begin
      @config = YAML.load_file CONFIG_FILE
      @config['projects'] ||= {}
      @user_id = @config['user_id']
      @workspace_id = @config['workspace_id']
      # puts "User: #{@user_id} Worskpace: #{@workspace_id}"
    rescue
      abort "Config error: ~/.asana-client.\nSee https://github.com/richgong/asana-ruby-script for instructions."
    end
  end

  def self.save
    File.open(CONFIG_FILE, 'w') {|f| f.write @config.to_yaml }
  end

  def self.parse(args)
    if args.empty?
      tasks = self.get "tasks?workspace=#{@workspace_id}&assignee=me&completed_since=now"
      show = false
      tasks["data"].each do |task|
        show = false if ['calendar:', 'inbox:'].any? { |x| task['name'].end_with?(x) }
        show = true if task['name'].end_with?('now:')
        #puts "#{task['id'].to_s.rjust(20)}) #{task['name']}" if show
        puts "#{"\t" if !task['name'].end_with?(':')}#{task['name']}" if show
      end
      exit
    end

    cmd = args.shift
    tags = args.select { |arg| arg.start_with? ':' }.map { |arg| arg[1..-1] }
    args = args.select { |arg| !arg.start_with? ':' }
    value = args.join ' '

    case cmd
    when 'd'
      if value =~ /^(\d+)$/
        self.put "tasks/#{$1}", { "completed" => true }
        puts "Task completed!"
      else
        puts "Missing task ID"
      end
    when 'p'
      projects = get_projects
      projects["data"].each do |project|
        puts project['name']
      end
    when 'n'
      exit if value.length == 0
      new_task = self.post "tasks", {
          "workspace" => @workspace_id,
          "name" => value,
          "assignee" => 'me'
      }
      # add task to project
      tags.each do |tag|
        project_id = ensure_project(tag)
        self.post "tasks/#{new_task['data']['id']}/addProject", { "project" => project_id } if project_id
      end
      puts "New task #{tags}: https://app.asana.com/0/0/#{new_task['data']['id']}"
    else
      abort "Unknown command: #{cmd}"
    end
  end

  def self.get_projects
    self.get "projects?workspace=#{@workspace_id}&archived=false"
  end

  def self.ensure_project(tag)
    return @config['projects'][tag] if @config['projects'][tag]
    puts "Looking up projects..."
    projects = get_projects
    projects["data"].each do |project|
      if project['name'] == tag
        @config['projects'][tag] = project['id']
        self.save
        return project['id']
      end
    end
    nil
  end

  def self.get(url)
    return self.http_request(Net::HTTP::Get, url, nil, nil)
  end

  def self.put(url, data, query = nil)
    return self.http_request(Net::HTTP::Put, url, data, query)
  end

  def self.post(url, data, query = nil)
    return self.http_request(Net::HTTP::Post, url, data, query)
  end

  def self.http_request(type, url, data, query)
    uri = URI.parse "https://app.asana.com/api/1.0/#{url}"
    # puts "s) #{uri}"
    http = Net::HTTP.new uri.host, uri.port
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    header = {
        "Content-Type" => "application/json"
    }
    req = type.new("#{uri.path}?#{uri.query}", header)
    req.basic_auth @config["api_key"], ''
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
