require_relative "./github"
require_relative "./rejection_log"
require_relative "./repo"

# Repos created on `day` that already have a few stars, best first.
#
# This list used to come from GitHub Archive: WatchEvents for repos that also
# had a CreateEvent that day. GitHub's public event feed stopped carrying
# repository CreateEvents in October 2025, so that query went empty. The search
# API answers the same question directly.
#
# Stars are the repo's total at the time we ask. For a repo created today
# that is today's stars, give or take the last few hours.
class NewRepos
  MIN_STARS = 10
  PAGES = 3

  attr_reader :day, :github

  def initialize day, github=GitHub.new
    @day = day
    @github = github
  end

  def top limit=15
    candidates
      .lazy
      .select { |repo| acceptable? repo }
      .first(limit)
  end

  private

  def candidates
    github.search_repositories("created:#{day} stars:>=#{MIN_STARS}", PAGES).map { |item|
      Repo.from_api item, item["stargazers_count"]
    }
  end

  def acceptable? repo
    reason = repo.rejection_reason
    RejectionLog.skipped day, repo.html_url, repo.stargazers_count, reason if reason
    reason.nil?
  end
end
