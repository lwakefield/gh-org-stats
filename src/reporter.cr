class Reporter
  def run
    db = DB.open "sqlite3://./data.db"
    merged_prs_per_repo = db.query_all("
      select
        owner,
        name,
        pull_number,
        title,
        opened_by,
        opened_at,
        merged_by,
        merged_at,
        comments,
        review_comments,
        commits,
        additions,
        deletions,
        changed_files
      from gh_merged_pulls
      join gh_repos using (repo_id);
    ", as: {
      owner:           String,
      name:            String,
      pull_number:     Int32,
      title:           String,
      opened_by:       String,
      opened_at:       Time,
      merged_by:       String,
      merged_at:       Time,
      comments:        Int32,
      review_comments: Int32,
      commits:         Int32,
      additions:       Int32,
      deletions:       Int32,
      changed_files:   Int32,
    }).group_by do |pr|
      pr[:owner] + "/" + pr[:name]
    end

    earliest = db.query_one "select min(merged_at) from gh_merged_pulls;", as: Time
    latest = db.query_one "select max(merged_at) from gh_merged_pulls;", as: Time

    backbone = [] of Time
    merge_throughput = {} of String => Array(Tuple(Time, Int32))
    p90_time_to_merge = {} of String => Array(Tuple(Time, Time::Span | Nil))
    p50_time_to_merge = {} of String => Array(Tuple(Time, Time::Span | Nil))

    earliest.at_beginning_of_week.step(to: latest, by: 1.week) do |date|
      backbone << date

      merged_prs_per_repo.each do |key, val|
        prs = val.select do |pr|
          date <= pr[:merged_at] && pr[:merged_at] < date + 1.week
        end

        merge_throughput[key] ||= [] of {Time, Int32}
        merge_throughput[key] << {date, prs.size}

        time_to_merge = prs.map do |pr|
          pr[:merged_at] - pr[:opened_at]
        end.sort

        p90_time_to_merge[key] ||= [] of {Time, Time::Span | Nil}
        p50_time_to_merge[key] ||= [] of {Time, Time::Span | Nil}
        if prs.size > 0
          p90_time_to_merge[key] << {date, time_to_merge[(time_to_merge.size * 0.9).floor.to_i32]}
          p50_time_to_merge[key] << {date, time_to_merge[(time_to_merge.size * 0.5).floor.to_i32]}
        else
          p90_time_to_merge[key] << {date, nil}
          p50_time_to_merge[key] << {date, nil}
        end
      end
    end

    merge_throughput_table = Table.new
    merge_throughput_table.cells << [""] + backbone.map(&.to_s)
    merge_throughput.map do |repo, series|
      merge_throughput_table.cells << [repo] + series.map { |v| v[1].to_s }
    end

    p90_time_to_merge_table = Table.new
    p90_time_to_merge_table.cells << [""] + backbone.map(&.to_s)
    p90_time_to_merge.map do |repo, series|
      p90_time_to_merge_table.cells << [repo] + series.map do |v|
        res = ""
        if v[1]
          res += "#{v[1].not_nil!.days}d" if v[1].not_nil!.days > 0
          res += "#{v[1].not_nil!.hours}h" if v[1].not_nil!.hours > 0
          res += "#{v[1].not_nil!.minutes}m" if v[1].not_nil!.minutes > 0
        end
        res
      end
    end

    p50_time_to_merge_table = Table.new
    p50_time_to_merge_table.cells << [""] + backbone.map(&.to_s)
    p50_time_to_merge.map do |repo, series|
      p50_time_to_merge_table.cells << [repo] + series.map do |v|
        res = ""
        if v[1]
          res += "#{v[1].not_nil!.days}d" if v[1].not_nil!.days > 0
          res += "#{v[1].not_nil!.hours}h" if v[1].not_nil!.hours > 0
          res += "#{v[1].not_nil!.minutes}m" if v[1].not_nil!.minutes > 0
        end
        res
      end
    end

    puts "# Merge Throughput\n\n"
    puts merge_throughput_table.to_markdown
    puts "\n"
    puts "# p90 Time To Merge\n\n"
    puts p90_time_to_merge_table.to_markdown
    puts "\n"
    puts "# p50 Time To Merge\n\n"
    puts p50_time_to_merge_table.to_markdown
    puts "\n"
  end
end

class Table
  # first row is the header
  property cells : Array(Array(String))

  def initialize
    @cells = [] of Array(String)
  end

  def cell_widths
    (0...cells.first.size).map do |i|
      cells.map { |row| row[i].size }.max
    end
  end

  def to_markdown
    widths = cell_widths

    res = ""

    res += "| " + cells.first.map_with_index do |header, i|
      header.ljust(widths[i])
    end.join(" | ") + " |\n"

    res += "|-" + widths.map { |w| "-" * w }.join("-|-") + "-|\n"

    res += cells[1..].map do |row|
      "| " + row.map_with_index do |cell, i|
        cell.ljust(widths[i])
      end.join(" | ") + " |"
    end.join("\n")

    res
  end
end
