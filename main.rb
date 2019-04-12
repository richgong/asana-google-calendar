#!/usr/bin/env ruby
#
# work: https://console.developers.google.com/apis/credentials?authuser=0&project=quickstart-1554304957185
# personal: https://console.developers.google.com/apis/credentials?authuser=0&project=quickstart-1554749225585
# help: https://developers.google.com/calendar/quickstart/ruby

require "json"
require "net/https"
require "yaml"
require 'fileutils'
require 'date'


class Main
  CONFIG_DIR = File.expand_path '~/asana-google-calendar/config'
  CONFIG_FILE = File.join CONFIG_DIR, 'config.yaml'
  DB_DIR = File.expand_path '~/Dropbox/Apps/asana-google-calendar'
  DB_FILE = "sqlite3://%s" % File.join(DB_DIR, 'sqlite.db')
  CALENDAR_CREDENTIALS_FILE = File.join CONFIG_DIR, 'calendar_credentials.json'
  CALENDAR_TOKEN_FILE = File.join CONFIG_DIR, 'calendar_token.yaml'
  CALENDAR_AUTH_URL = 'urn:ietf:wg:oauth:2.0:oob'.freeze
  TAB  = '  - '
  TAB2 = '>>> '
  TAB3 = '    '

  def initialize
    @calendar = nil
    @db = nil
    @free_total = 0
    @free_spent = 0
    begin
      @config = YAML.load_file CONFIG_FILE
      @config['projects'] ||= {}
      @emails = @config['emails']
      @user_id = @config['user_id']
      @workspace_id = @config['workspace_id']
    rescue
      abort "Config error: #{CONFIG_FILE}\nSee https://github.com/richgong/asana-google-calendar for instructions."
    end
  end

  def calendar
    require 'google/apis/calendar_v3'
    require 'googleauth'
    require 'googleauth/stores/file_token_store'
    return @calendar if !@calendar.nil?
    client_id = Google::Auth::ClientId.from_file(CALENDAR_CREDENTIALS_FILE)
    token_store = Google::Auth::Stores::FileTokenStore.new(file: CALENDAR_TOKEN_FILE)
    authorizer = Google::Auth::UserAuthorizer.new(client_id, Google::Apis::CalendarV3::AUTH_CALENDAR_READONLY, token_store)
    user_id = 'default'
    credentials = authorizer.get_credentials(user_id)
    if credentials.nil?
      url = authorizer.get_authorization_url(base_url: CALENDAR_AUTH_URL)
      puts "Open this URL and enter the resulting authorization code:\n#{url}"
      code = STDIN.gets
      credentials = authorizer.get_and_store_credentials_from_code(
          user_id: user_id, code: code, base_url: OOB_URI
      )
    end
    @calendar = Google::Apis::CalendarV3::CalendarService.new
    @calendar.authorization = credentials
    @calendar
  end

  def db
    require_relative './sprint.rb'
    return @db if !@db.nil?
    @db = ActiveRecord::Base.establish_connection(DB_FILE)
    # @db ||= SQLite3::Database.new DB_FILE, {results_as_hash: true}
    @db = ActiveRecord::Base.connection
  end

  def save
    File.open(CONFIG_FILE, 'w') {|f| f.write @config.to_yaml }
  end

  def change_time t, h=0, m=0, s=0
    DateTime.new(t.year, t.month, t.day, h, m, s, t.zone)
  end

  def duration delta, show_secs=false
    delta = delta.to_i
    seconds = delta % 60
    minutes = (delta / 60) % 60
    hours = delta / (60 * 60)
    return "%d:%02d:%02d" % [hours, minutes, seconds] if show_secs
    "%d:%02d" % [hours, minutes]
  end

  def timedelta a, b=nil, show_secs=false
    b ||= DateTime.now
    duration (b.to_time.to_i - a.to_time.to_i), show_secs
  end

  def event_time t
    return t.date || t.date_time
  end

  def symbolize_response_status status
    case status
    when 'accepted'
      return '_'
    when 'needsAction'
      return '?'
    when 'tentative'
      return '~'
    when 'declined'
      return '^'
    else
      status
    end
  end

  def clean_name p
    return "me" if p.self || @emails.include?(p.email)
    return p.display_name if p.display_name
    return p.email.sub(/@.*$/, '')
  end

  def print_attendee p
    puts "#{TAB3}#{symbolize_response_status(p.response_status)} #{'* ' if p.organizer}#{clean_name(p)}" if !(p.resource)
  end

  def print_event event, event_start, event_end, is_next, is_details=false
    now = DateTime.now
    is_now = event_start < now && now < event_end
    puts "#{is_details ? "\n#{TAB2}" : TAB}#{event_start.strftime('%H:%M')} #{timedelta(event_start, event_end)} #{"* " if is_now}#{event.summary}"
    puts "#{TAB3}@ #{event.location.gsub("\n", " ")}" if (event.location && is_next)

    if is_details
      # puts JSON.pretty_generate(event.to_h)
      puts "#{TAB3}#{event.html_link}"
      # puts "#{TAB3}Hangout: #{event.hangout_link}"
      if event.attendees
        event.attendees.each do |p|
          print_attendee p
        end
      end
      require 'nokogiri'
      desc = Nokogiri::HTML(event.description.gsub(/<li>/i, "\n  - ").gsub(/<br>/i, "\n").gsub(/<[^>]+>/, "\n")).text.squeeze("\n") if event.description
      puts "\n>>>\n#{desc}\n<<<" if desc
    end
  end

  def print_free now, last_event_end, next_event_start, show_details
    is_now = last_event_end < now && now < next_event_start
    puts "#{TAB}#{last_event_end.strftime('%H:%M')} #{timedelta(last_event_end, next_event_start)} #{"* " if is_now}" if show_details != :details_next_only
    amount = next_event_start.to_time.to_f - last_event_end.to_time.to_f
    @free_total += amount
    if is_now
      @free_spent += now.to_time.to_f - last_event_end.to_time.to_f
    elsif now >= next_event_start
      @free_spent += amount
    end
  end

  def print_calendar date_delta, show_details
    now = DateTime.now
    start_date = now + date_delta
    today = change_time start_date
    tomorrow = change_time (start_date + 1)
    events = @emails.reduce([]) do |events, email|
      response = calendar.list_events(email, # calendar id
                                      max_results: 10,
                                      single_events: true,
                                      order_by: 'startTime',
                                      time_min: today.rfc3339,
                                      time_max: tomorrow.rfc3339)
      events + response.items
    end.
        uniq { |event| event.id }.
        sort_by { |event| event_time(event.start)  }

    puts "\ncalendar: #{"%+d" % date_delta if date_delta != 0}"
    next_bound = nil
    last_event = nil
    is_first = true
    events.each do |event|
      if event.attendees
        rsvp = event.attendees.select { |rsvp| @emails.include?(rsvp.email) }.any? {|rsvp| ['tentative', 'needsAction', 'accepted'].include?(rsvp.response_status)}
        next if !rsvp
      end
      is_next = false
      event_start = event_time(event.start)
      event_end = event_time(event.end)
      if is_first and event_start.hour > 10
        start_of_day = change_time(start_date, 10)
        print_free now, start_of_day, event_start, show_details
      end
      if next_bound.nil?
        if event_start >= now
          next_bound = event_start
          is_next = true
        elsif event_end >= now + 10.0 / (24 * 60)
          next_bound = event_end
          is_next = true
        end
      end
      if last_event && event_time(last_event.end) < event_start
        print_free now, event_time(last_event.end), event_start, show_details
      end
      is_details = show_details == :details_all || (is_next && show_details == :details_next_only)
      print_event(event, event_start, event_end, is_next, is_details) if is_details || show_details != :details_next_only
      last_event = event
      is_first = false
    end
    end_of_day = change_time start_date, 18
    if last_event
      if event_time(last_event.end) < end_of_day
        print_free now, event_time(last_event.end), end_of_day, show_details
      end
    else
      print_free now, change_time(start_date, 10 ), end_of_day, show_details
    end
    puts "\ntime: #{next_bound.nil? ? 'none' : timedelta(now, next_bound, true)} / #{duration(@free_spent)} / #{duration(@free_total)}"
  end

  def print_tasks
    tasks = http_get "tasks?workspace=#{@workspace_id}&assignee=me&completed_since=now"
    show = false
    puts
    tasks["data"].each do |task|
      show = false if ['calendar:', 'inbox:'].any? { |x| task['name'].end_with?(x) }
      show = true if task['name'].end_with?('now:')
      #puts "#{task['id'].to_s.rjust(20)}) #{task['name']}" if show
      puts "#{TAB if !task['name'].end_with?(':')}#{task['name']}" if show
    end
  end

  def print_tasks_and_calendar date_delta=0, show_details=:details_none
    print_sprints date_delta
    print_tasks
    print_calendar date_delta, show_details
  end

  def print_sprint sprint
    puts "#{TAB}#{sprint.started_at_dt.strftime('%H:%M')} #{sprint.actual ? "#{duration(sprint.actual, true)} /" : "#{timedelta(sprint.started_at_dt, DateTime.now, true)} *"} #{duration(sprint.estimate, true)} #{sprint.goal} #{"# #{sprint.note}" if sprint.note && !sprint.note.empty?} "
  end

  def print_sprints date_delta=0
    db # require
    puts "sprints: #{"%+d" % date_delta if date_delta != 0}"
    now = DateTime.now + date_delta
    Sprint.where('started_at BETWEEN ? AND ?', change_time(now), change_time(now + 1)).each do |sprint|
      print_sprint sprint
    end
  end

  def run(args)
    if args.empty?
      print_tasks_and_calendar
      exit
    end

    cmd = args.shift
    value = args.join ' '
    case cmd
    when /^([\-\+0-9]+)/ # print status +/- days
      print_tasks_and_calendar($1.to_i)
    when /c([\-\+0-9]*)/ # show first calendar detail
      print_calendar($1.to_i, :details_next_only)
    when /a([\-\+0-9]*)/ # show all details
      print_tasks_and_calendar($1.to_i, :details_all)
    when 'cl' # calendars
      calendar.list_calendar_lists().items.each do |cal|
        puts "calendar: #{cal.to_h}"
      end
    when 'pr' # projects
      projects = get_projects
      projects["data"].each do |project|
        puts project['name']
      end
    when 'n' # new task
      if value.empty?
        print "New task: "
        value = STDIN.gets.chomp
      end
      exit if value.empty?
      tags = value.scan(/:([a-z]+)/).map { |x| x[0] }
      value = value.gsub(/:[a-z]+/, '')
      new_task = http_post "tasks", {
          "workspace" => @workspace_id,
          "name" => value,
          "assignee" => 'me'
      }
      # add task to project
      tags.each do |tag|
        project_id = ensure_project(tag)
        http_post "tasks/#{new_task['data']['id']}/addProject", { "project" => project_id } if project_id
      end
      puts "New task #{tags}: https://app.asana.com/0/0/#{new_task['data']['id']}"
    when 's' # new sprint
      db # require
      sprint = Sprint.order(started_at: :desc).first
      sprint = nil if sprint.actual
      if !sprint.nil?
        puts "!!! Sprint still running:"
        print_sprint sprint
      end
      if value.empty?
        print "New sprint: "
        value = STDIN.gets.chomp
      end
      if value.empty?
        if sprint
          value = sprint.goal
        else
          exit
        end
      end
      print "Minutes estimate? "
      estimate = STDIN.gets.chomp
      estimate = (estimate.empty? ? 5.0 : estimate.to_f) * 60.0

      sprint = Sprint.new(started_at: DateTime.now) if not sprint
      sprint.goal = value
      sprint.estimate = estimate
      sprint.save!

      print_sprints
    when 'd' # complete sprint
      # if value =~ /^(\d+)$/
      #   http_put "tasks/#{$1}", { "completed" => true }
      #   puts "Task completed!"
      # else
      #   puts "Missing task ID"
      # end
      db # require
      sprint = Sprint.order(started_at: :desc).first
      puts "finished: #{sprint.goal}"
      actual = DateTime.now.to_time.to_f - sprint.started_at_dt.to_time.to_f
      puts "estimate: #{duration(sprint.estimate, true)}"
      puts "actual:   #{duration(actual, true)}"
      print "note? "
      note = STDIN.gets.chomp
      sprint.note = note
      sprint.actual = actual
      sprint.save!
    when 'si' # init Sprint DB
      FileUtils.mkdir_p DB_DIR
      db.execute <<-SQL
CREATE TABLE sprints (
  started_at TEXT PRIMARY KEY,
  goal       TEXT,
  note       TEXT,
  estimate   REAL,
  actual     REAL
);
      SQL
    when 'sh'
      require 'pry'
      db
      binding.pry
    when '-h'
    when '--help'
      puts "Usage: todo [COMMAND] [ARGS]

Commands:
  [none]            sprints, tasks, and calendar
  +1 | -1           sprints, tasks, and calendar: +1 or -1 days ahead
  c | c+1 | c-1     calendar event details (+1 or -1 days ahead)
  a | a+1 | a-1     tasks, with calendar event details (+1 or -1 days ahead)
  cl                list of calendars
  pr                list of projects
  n [task] [:tag]   new todo
  p                 new sprint (pomodoro)
  d                 complete a sprint
"
    else
      abort "Unknown command: #{cmd}"
    end
  end

  def get_projects
    http_get "projects?workspace=#{@workspace_id}&archived=false"
  end

  def ensure_project(tag)
    return @config['projects'][tag] if @config['projects'][tag]
    puts "Looking up projects..."
    projects = get_projects
    projects["data"].each do |project|
      @config['projects'][project['name']] = project['id']
    end
    save
    return @config['projects'][tag]
  end

  def http_get(url)
    return http_request(Net::HTTP::Get, url, nil, nil)
  end

  def http_put(url, data, query = nil)
    return http_request(Net::HTTP::Put, url, data, query)
  end

  def http_post(url, data, query = nil)
    return http_request(Net::HTTP::Post, url, data, query)
  end

  def http_request(type, url, data, query)
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
  m = Main.new
  m.run ARGV
end
