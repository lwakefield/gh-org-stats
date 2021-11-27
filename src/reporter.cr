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

        prs.each do |pr|
          # puts "gh_pr.time_to_merge_seconds{owner=\"#{pr[:owner]}\",name=\"#{pr[:name]}\"} #{(pr[:merged_at] - pr[:opened_at]).total_seconds} #{pr[:merged_at].to_unix_ms}"
          puts({
            name: "test.gh_pr.time_to_merge_seconds",
            tags: {
              owner: pr[:owner],
              name: pr[:name]
            },
            value: (pr[:merged_at] - pr[:opened_at]).total_seconds,
            timestamp: pr[:merged_at].to_rfc3339
          }.to_json)
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
  end
end
