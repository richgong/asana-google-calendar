#!/usr/bin/env ruby
#
if __FILE__ == $0
  if ARGV.length > 0
    args = ARGV.join(' ')
  else
    print "Enter numbers: "
    args = STDIN.gets
  end
  args = args.strip.gsub(/\s+/, ' ').split(' ')
  args.each do |x|
    puts x.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end
end

