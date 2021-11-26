require "sqlite3"

require "./updater.cr"
require "./reporter.cr"

if ARGV.first? == "update"
  owners = ARGV[1]? || ""
  if owners.empty?
    print_help
    exit 1
  end

  owners = owners.split(",").map(&.strip).reject(&.empty?)

  Updater.new.run owners
elsif ARGV.first? == "report"
  Reporter.new.run
end


def print_help
  puts "usage: gh-org-stats update <orgs> where orgs is comma separated"
end
