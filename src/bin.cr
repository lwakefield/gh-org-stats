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
  output_dir = ARGV[1]? || ""
  if output_dir.empty?
    print_help
    exit 1
  end

  Reporter.new(output_dir).run
end


def print_help
  puts "usage: gh-org-stats update <orgs> where orgs is comma separated"
  puts "       gh-org-stats report <output-dir>"
end
