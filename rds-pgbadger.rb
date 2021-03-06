#!/usr/bin/env ruby

# Original script source: https://github.com/sportngin/rds-pgbadger

require 'optparse'
require 'yaml'
require 'ox'
require 'aws-sdk-core'

options = {}
OptionParser.new do |opts|
    opts.banner = "Usage: rds-pgbadger.rb [options]"

    opts.on('-e', '--env NAME', 'Environement name') { |v| options[:env] = v }
    opts.on('-i', '--instance-id NAME', 'RDS instance identifier') { |v| options[:instance_id] = v }
    opts.on('-d', '--date DATE', 'Filter logs to given date in format YYYY-MM-DD.') { |v| options[:date] = v }

end.parse!

raise OptionParser::MissingArgument.new(:env) if options[:env].nil?
raise OptionParser::MissingArgument.new(:instance_id) if options[:instance_id].nil?

creds = YAML.load(File.read(File.expand_path('~/.fog')))

puts "Instantiating RDS client for #{options[:env]} environment."
rds = Aws::RDS::Client.new(
  region: 'us-east-1',
  access_key_id: creds[options[:env]]['aws_access_key_id'],
  secret_access_key: creds[options[:env]]['aws_secret_access_key']
)
log_files = rds.describe_db_log_files(db_instance_identifier: options[:instance_id], filename_contains: "postgresql.log.#{options[:date]}")[:describe_db_log_files].map(&:log_file_name)

dir_name = "#{options[:instance_id]}"

if !File.directory?("out")
  Dir.mkdir("out")
end

if !File.directory?("out/#{dir_name}")
  Dir.mkdir("out/#{dir_name}")
end

if !File.directory?("out/#{dir_name}/error")
  Dir.mkdir("out/#{dir_name}/error")
end

log_files.each do |log_file|
  puts "Downloading log file: #{log_file}"
  open("out/#{dir_name}/#{log_file}", 'w') do |f|
    rds.download_db_log_file_portion(db_instance_identifier: options[:instance_id], log_file_name: log_file).each do |r|
      print "."
      f.puts r[:log_file_data]
    end
    puts "."
  end
  puts "Saved log to out/#{dir_name}/#{log_file}."
end

# Remove report file as the cronjob does not seems to be able to overwrite it
File.delete("out/#{dir_name}/#{dir_name}.html") if File.exist?("out/#{dir_name}/#{dir_name}.html")

puts "Generating PG Badger report."
`/usr/local/bin/pgbadger --prefix "%t:%r:%u@%d:[%p]:" --outfile out/#{dir_name}/index.html out/#{dir_name}/error/*.log.*`
