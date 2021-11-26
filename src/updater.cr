require "log"
require "json"

require "sqlite3"

require "./gh_client.cr"

class Updater
  def get_db_client
    DB.open "sqlite3://./data.db"
  end

  def setup_db_schemas (db)
    db.exec "create table if not exists gh_repos (
    repo_id number primary key,
    owner text,
    name text
  )"
    db.exec "create table if not exists gh_merged_pull_sync_points (
    repo_id number primary key,
    page number
  )"
    db.exec "create table if not exists gh_merged_pulls (
    pull_id         number primary key,
    repo_id         number,
    pull_number     number,
    title           text,
    opened_by       text,
    opened_at       text,
    merged_by       text,
    merged_at       text,
    comments        number,
    review_comments number,
    commits         number,
    additions       number,
    deletions       number,
    changed_files   number
  )"
  end

  def update_repos (orgs, db)
    client = GitHubClient.new

    orgs.each do |org|
      (1..).each do |page|
        res = client.get "/orgs/#{org}/repos?per_page=100&page=#{page}&sort=created&direction=asc"

        repos = JSON.parse res.body

        break if repos.as_a.empty?

        repos.as_a.each do |repo|
          db.exec "insert into gh_repos (repo_id, owner, name)
        values (?, ?, ?)
        on conflict (repo_id) do update set
          owner=excluded.owner,
          name=excluded.name
      ", repo.as_h["id"].as_i, repo.as_h["owner"].as_h["login"].as_s, repo.as_h["name"].as_s
        end
        Log.info { "Fetched repos.page=#{page}" }
      end
    end
  end

  def update_merged_pulls (repo_id, db)
    client = GitHubClient.new

    repo = db.query_one "select owner, name from gh_repos where repo_id=?",
        args: [repo_id],
        as: {owner: String, name: String}
    owner, repo = repo[:owner], repo[:name]

    startpage = db.query_one? "select page from gh_merged_pull_sync_points where repo_id=?",
      args: [repo_id],
      as: Int32
      startpage = 1 if startpage.nil?

    Log.info { "Starting repo=#{owner}/#{repo} from page=#{startpage}" }

    (startpage..).each do |page|
      res = client.get "/repos/#{owner}/#{repo}/pulls?per_page=100&page=#{page}&state=closed&sort=created&direction=asc"
      begin
        pulls = JSON.parse res.body
      rescue e
        pp res.body
        raise e
      end

      break if pulls.as_a.empty?

      pulls.as_a.each do |pull|
        res = client.get "/repos/#{owner}/#{repo}/pulls/#{pull.as_h["number"].as_i}"
        begin
          pull_details = JSON.parse res.body
        rescue e
          pp res.body
          raise e
        end

        next unless pull_details.as_h["merged"].as_bool

        db.exec("insert into gh_merged_pulls (
          pull_id,
          repo_id,
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
        )
        values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        on conflict (pull_id) do update set
          pull_id         = excluded.pull_id,
          repo_id         = excluded.repo_id,
          pull_number     = excluded.pull_number,
          title           = excluded.title,
          opened_by       = excluded.opened_by,
          opened_at       = excluded.opened_at,
          merged_by       = excluded.merged_by,
          merged_at       = excluded.merged_at,
          comments        = excluded.comments,
          review_comments = excluded.review_comments,
          commits         = excluded.commits,
          additions       = excluded.additions,
          deletions       = excluded.deletions,
          changed_files   = excluded.changed_files
      ",
      pull_details.as_h["id"].as_i,
      pull_details.dig("base", "repo", "id").as_i,
      pull_details.as_h["number"].as_i,
      pull_details.as_h["title"].as_s,
      (pull_details.dig?("user", "login") || JSON::Any.new "ghost").as_s,
      Time.parse_iso8601(pull_details.as_h["created_at"].as_s),
      (pull_details.dig?("merged_by", "login") || JSON::Any.new "ghost").as_s,
      Time.parse_iso8601(pull_details.as_h["merged_at"].as_s),
      pull_details.as_h["comments"].as_i,
      pull_details.as_h["review_comments"].as_i,
      pull_details.as_h["commits"].as_i,
      pull_details.as_h["additions"].as_i,
      pull_details.as_h["deletions"].as_i,
      pull_details.as_h["changed_files"].as_i
        )
      end

      db.exec "insert into gh_merged_pull_sync_points (repo_id, page)
      values (?, ?)
      on conflict (repo_id) do update set
        page=excluded.page
    ", repo_id, page
    Log.info { "Fetched repo=#{owner}/#{repo} merged_pulls.page=#{page}" }
    end
  end

  def run (owners)
    db = get_db_client
    setup_db_schemas db
    update_repos owners, db

    repos = db.query_all "select repo_id from gh_repos", as: Int32
    repos.each do |repo_id|
      update_merged_pulls repo_id, db
    end
  end
end
