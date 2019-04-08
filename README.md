# asana-calendar-script

A simple Ruby script for calling Asana and Google Calendar from the command-line.

Inspired by this: [asana-client](https://github.com/tmacwill/asana-client) -- but dramatically simplified, and also added Google calendar integration.

# Why?

There's a few existing Asana commandline clients. But they're one of the following:

- Installed via `gem install`
- Installed via `brew install`

I find it easier to just make it a simple ruby script, and call it via a Bash alias.

This way, I can just edit the script -- and not worry about having to publish a brew or gem package.

# To install

First, get an `api_key`:

- Open up Asana web app
- Open "My Profile Settings"
- Open the tab "Apps"
- Click "Manage Developer Apps"
- Click "+ Create New Personal Access Token"
- Copy the secret API key

Then figure out what your `user_id` and `workspace_id` are:

- [https://app.asana.com/api/1.0/users](https://app.asana.com/api/1.0/users)
- [https://app.asana.com/api/1.0/workspaces](https://app.asana.com/api/1.0/workspaces)

Then create a file at `~/asana-calendar-script/config/config.yaml`, like this:

	api_key: 0/111111
	workspace_id: 1111111
	user_id: 1111111

Then, clone this repo.

Then, make an alias in your `.bash_profile` to call the script in this repo. I have something like this in my `.bash_profile`:

	alias asana="~/asana-calendar-script/main.rb"

# Usage

    # show tasks assigned to me
    asana
    
    # new task for me
    asana n <task description>
    asana n Take out the trash
    
    # complete a task
    asana d <task_id>
    
    # list projects
    asana p
