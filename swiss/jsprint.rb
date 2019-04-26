#!/usr/bin/env ruby

require 'json'

print "Enter JSON string: "
s = STDIN.gets
j = JSON.parse s
puts JSON.pretty_generate(j)