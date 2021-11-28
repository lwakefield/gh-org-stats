require "ecr"

require "./color.cr"

class Reporter
  getter output_dir
  def initialize (@output_dir="./report")
  end

  def run
    db = DB.open "sqlite3://./data.db"
    merged_prs = db.query_all("
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
    })
    merged_prs_per_repo = merged_prs.group_by do |pr|
      pr[:owner] + "/" + pr[:name]
    end

    earliest = merged_prs.map(&.[:merged_at]).min
    latest   = merged_prs.map(&.[:merged_at]).max

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

    Dir.mkdir_p(output_dir)
    Dir.mkdir_p("#{output_dir}/charts")

    write_throughput_heatmap(merge_throughput)
    write_throughput_bars(merged_prs)
    write_time_to_merge_bars(merged_prs)
    File.write("#{output_dir}/readme.md", <<-HERE
    protip: right click and "open image in new tab" to get tooltips + click to copy to clipboard.

    # Merge Throughput: Total

    <img src="./charts/throughput_bars.svg" />

    # Merge Throughput: Per Repository

    <img src="./charts/throughput_heatmap.svg" />

    # Mean Time To Merge:

    <img src="./charts/time_to_merge_bars.svg" />
    HERE
    )
  end

  def write_throughput_heatmap (merge_throughput)
    File.write(
      "#{output_dir}/charts/throughput_heatmap.svg",
      ECR.render "#{__DIR__}/templates/throughput_heatmap.svg.ecr"
    )
  end

  def write_throughput_bars (merged_prs)
    series = merged_prs.group_by do |v|
      v[:merged_at].at_beginning_of_week
    end.transform_values(&.size).to_a.sort_by(&.first)

    fmt_tooltip = ->(x: Time, y: Int32) { "date=#{x}, merged=#{y}" }
    File.write(
      "#{output_dir}/charts/throughput_bars.svg",
      ECR.render "#{__DIR__}/templates/bars.svg.ecr"
    )
  end

  def write_time_to_merge_bars (merged_prs)
    series = merged_prs.group_by do |v|
      v[:merged_at].at_beginning_of_week
    end.transform_values do |samples|
      time_to_merge = samples.map{ |s| (s[:merged_at] - s[:opened_at]).total_seconds }
      time_to_merge.sum / time_to_merge.size
    end.to_a.sort_by(&.first)

    fmt_tooltip = ->(x: Time, y: Float64) {
      span = Time::Span.new(seconds: y.to_i32)
      span_fmt = ""
      span_fmt += "#{span.days}d" if span.days > 0
      span_fmt += "#{span.hours}h" if span.hours > 0
      span_fmt += "#{span.minutes}m" if span.minutes > 0

      "date=#{x}, time_to_merge=#{span_fmt}"
    }
    File.write(
      "#{output_dir}/charts/time_to_merge_bars.svg",
      ECR.render "#{__DIR__}/templates/bars.svg.ecr"
    )
  end
end
