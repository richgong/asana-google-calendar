#!/usr/bin/env ruby
#
# work: https://console.developers.google.com/apis/credentials?authuser=0&project=quickstart-1554304957185
# personal: https://console.developers.google.com/apis/credentials?authuser=0&project=quickstart-1554749225585
# help: https://developers.google.com/calendar/quickstart/ruby

require "json"
require "net/https"
require "yaml"
require 'fileutils'
require 'google/apis/calendar_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'date'
require 'fileutils'


module Main
  CONFIG_DIR = File.expand_path '~/asana-google-calendar/config'
  CONFIG_FILE = File.join CONFIG_DIR, 'config.yaml'
  CALENDAR_CREDENTIALS_FILE = File.join CONFIG_DIR, 'calendar_credentials.json'
  CALENDAR_TOKEN_FILE = File.join CONFIG_DIR, 'calendar_token.yaml'
  CALENDAR_SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR_READONLY
  CALENDAR_AUTH_URL = 'urn:ietf:wg:oauth:2.0:oob'.freeze
  TAB = '  - '
  def self.init
    @calendar = nil
    begin
      # FileUtils.mkdir_p CONFIG_DIR
      @config = YAML.load_file CONFIG_FILE
      @config['projects'] ||= {}
      @emails = @config['emails']
      @user_id = @config['user_id']
      @workspace_id = @config['workspace_id']
    rescue
      abort "Config error: #{CONFIG_FILE}\nSee https://github.com/richgong/asana-ruby-script for instructions."
    end
  end

  def self.ensure_calendar
    return @calendar if !@calendar.nil?
    client_id = Google::Auth::ClientId.from_file(CALENDAR_CREDENTIALS_FILE)
    token_store = Google::Auth::Stores::FileTokenStore.new(file: CALENDAR_TOKEN_FILE)
    authorizer = Google::Auth::UserAuthorizer.new(client_id, CALENDAR_SCOPE, token_store)
    user_id = 'default'
    credentials = authorizer.get_credentials(user_id)
    if credentials.nil?
      url = authorizer.get_authorization_url(base_url: CALENDAR_AUTH_URL)
      puts "Open this URL and enter the resulting authorization code:\n#{url}"
      code = gets
      credentials = authorizer.get_and_store_credentials_from_code(
          user_id: user_id, code: code, base_url: OOB_URI
      )
    end
    @calendar = Google::Apis::CalendarV3::CalendarService.new
    @calendar.authorization = credentials
    @calendar
  end

  def self.save
    File.open(CONFIG_FILE, 'w') {|f| f.write @config.to_yaml }
  end

  def self.zero_time t
    DateTime.new(t.year, t.month, t.day, 0, 0, 0, t.zone)
  end

  def self.print_calendar start_date=nil
    start_date ||= DateTime.now
    today = zero_time start_date
    tomorrow = zero_time (start_date + 1)
    events = @emails.reduce([]) do |events, email|
      response = ensure_calendar.list_events(email, # calendar id
                                  max_results: 10,
                                  single_events: true,
                                  order_by: 'startTime',
                                  time_min: today.rfc3339,
                                  time_max: tomorrow.rfc3339)
      events + response.items
    end.
        uniq { |event| event.id }.
        sort_by { |event| event.start.date || event.start.date_time  }
    puts "\ncalendar:"
    next_event = nil
    events.each do |event|
      rsvp = event.attendees.select { |rsvp| @emails.include?(rsvp.email) }.any? {|rsvp| ['tentative', 'needsAction', 'accepted'].include?(rsvp.response_status)}
      next if !rsvp
      is_next = false
      event_start = event.start.date || event.start.date_time
      if next_event.nil? and event_start >= DateTime.now
        next_event = event
        is_next = true
      end
      puts "#{TAB}#{event_start.strftime('%H:%M')} #{"* " if is_next}#{event.summary} #{"-- #{event.location}" if event.location}"
    end
    if !next_event.nil?
      delta = ((next_event.start.date || next_event.start.date_time).to_time.to_i - DateTime.now.to_time.to_i)
      seconds = delta % 60
      minutes = (delta / 60) % 60
      hours = delta / (60 * 60)
      puts "next: #{format("%02d:%02d:%02d", hours, minutes, seconds)}"
    end
  end

  def self.parse(args)
    if args.empty?
      tasks = self.get "tasks?workspace=#{@workspace_id}&assignee=me&completed_since=now"
      show = false
      tasks["data"].each do |task|
        show = false if ['calendar:', 'inbox:'].any? { |x| task['name'].end_with?(x) }
        show = true if task['name'].end_with?('now:')
        #puts "#{task['id'].to_s.rjust(20)}) #{task['name']}" if show
        puts "#{TAB if !task['name'].end_with?(':')}#{task['name']}" if show
      end
      print_calendar
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
    when /^t([0-9]+)/
      print_calendar DateTime.now + $1.to_i
    when 'c'
      ensure_calendar.list_calendar_lists().items.each do |cal|
        puts "calendar: #{cal.to_h}"
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
      @config['projects'][project['name']] = project['id']
    end
    self.save
    return @config['projects'][tag]
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
  Main.init
  Main.parse ARGV
end
