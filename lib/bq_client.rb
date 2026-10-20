require "json"
require "big_query"

class BqClient
  attr_reader :bq, :day
  def initialize day
    @day = day
    @bq = BigQuery::Client.new({
      "client_id"     => ENV.fetch("BQ_CLIENT_ID"),
      "service_email" => ENV.fetch("BQ_SERVICE_EMAIL"),
      "key"           => ENV.fetch("BQ_KEY", "bq-key.p12"),
      "project_id"    => ENV.fetch("BQ_PROJECT_ID", "changelog-nightly")
    })
  end

  # `limit` is how many repos we want back; `max_lookups` caps GitHub API
  # calls. Spam (often already deleted by GitHub) can crowd the top of the
  # BigQuery results, so we keep looking until we have `limit` repos that pass.
  def top_all limit=15, max_lookups=200
    response_to_repo_list bq.query(top_all_sql), limit, max_lookups
  end

  def top_new limit=15, max_lookups=200
    response_to_repo_list bq.query(top_new_sql), limit, max_lookups
  end

  private

  def response_to_repo_list query_result, limit, max_lookups
    (query_result["rows"] || [])
      .map { |row| extract_fields_from_row row }
      .reject { |row| row[:url].malware? } # run before GH API (rate limits)
      .first(max_lookups) # run before GH API (rate limits)
      .lazy
      .map { |row| repo_from_row row }
      .reject(&:nil?)
      .first(limit)
  end

  def repo_from_row row
    repo = Repo.from_github row[:url], row[:count]
    reason = rejection_reason repo

    if reason
      log_rejection row, reason
      nil
    else
      repo
    end
  rescue => e
    log_rejection row, "#{e.class}: #{e.message}"
    nil
  end

  def rejection_reason repo
    return "blocked" if repo.blocked?
    return "malware" if repo.malware? # run it again now that we have more info
    return "description too short" if repo.description_too_short?
    return "description too long" if repo.description_too_long?
    return "obscene" if repo.obscene?
    return "too many new stars" if repo.too_many_new_stars?
  end

  def log_rejection row, reason
    $stderr.puts "[nightly] #{day} skipped #{row[:url]} (#{row[:count]} stars): #{reason}"
  end

  # each `row` hash has this format:
  # {"f"=>[{"v"=>"https://...snip..."}, {"v"=>"45"}]}
  def extract_fields_from_row row
    {
      url: row["f"].first["v"],
      count: row["f"].last["v"].to_i
    }
  end

  def top_all_sql
    <<-SQL
    SELECT repo.url, COUNT(repo.name) as count FROM
    TABLE_DATE_RANGE([githubarchive:day.],
      TIMESTAMP("#{day}"),
      TIMESTAMP("#{day}")
    )
    WHERE type="WatchEvent"
    GROUP BY repo.id, repo.name, repo.url
    HAVING count >= 50
    ORDER BY count DESC
    LIMIT 1000
    SQL
  end

  def top_new_sql
    <<-SQL
    SELECT repo.url, COUNT(repo.name) AS count FROM
    TABLE_DATE_RANGE([githubarchive:day.],
      TIMESTAMP("#{day}"),
      TIMESTAMP("#{day}")
    )
    WHERE type="WatchEvent"
    AND repo.url IN (
      SELECT repo.url FROM (
        SELECT repo.url,
          JSON_EXTRACT(payload, '$.ref_type') AS ref_type,
        FROM (TABLE_DATE_RANGE([githubarchive:day.],
          TIMESTAMP("#{day}"),
          TIMESTAMP("#{day}")
        ))
        WHERE type IN ("CreateEvent", "PublicEvent")
      )
      WHERE ref_type='"repository"' OR ref_type IS NULL # PublicEvent has no ref_type
    )
    GROUP BY repo.id, repo.name, repo.url
    HAVING count >= 10
    ORDER BY count DESC
    LIMIT 1000
    SQL
  end
end
