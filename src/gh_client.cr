require "http/client"
require "log"
require "uri"

class GitHubClient
  @ratelimit_remaining : Int32 | Nil
  @ratelimit_reset : Time | Nil

  def initialize
    @client = HTTP::Client.new(URI.parse "https://api.github.com")
    @client.basic_auth("", ENV["GH_API_KEY"])
  end

  def get (url)
    if @ratelimit_remaining == 0
      wait_time = @ratelimit_reset.not_nil! - Time.local + 1.minute
      Log.warn { "Hit ratelimit. Waiting #{wait_time}" }

      sleep wait_time
    end

    res = @client.get url
    @ratelimit_remaining = res.headers["x-ratelimit-remaining"].to_i32
    @ratelimit_reset     = Time.unix(res.headers["x-ratelimit-reset"].to_i32)
    res
  end
end
