require "pry"
require "hashie/mash"
require "yaml"
require "obscenity"
require "whatlanguage"
require "open-uri"
require_relative "./core_ext/string"

class Repo < Hashie::Mash
  OBSCENITY_SUBSTRING_MIN = 5

  def self.from_github url, stars_count
    repo = new JSON.load open(url, "Authorization" => %{token #{ENV["GITHUB_TOKEN"]}})
    repo.new_stargazers_count = stars_count
    repo.description = (repo.description || "").html_escape
    repo
  end

  def self.from_json hash
    new hash
  end

  def initialize hash={}
    super hash
    self.occurrences = 1
  end

  def blocked?
    blocked_github_repo_ids.include?(id) ||
    blocked_github_user_ids.include?(owner.id)
  end

  def classy_description
    description.linkify.emojify
  end

  def text_description
    description.html_unescape
  end

  def description
    self[:description] || ""
  end

  def english?
    WhatLanguage.new(:all).language(description) == :english
  end

  def language_class
    case language
    when "c#" then "csharp"
    else
      language.downcase.strip.gsub(" ", "-").gsub(/[^\w-]/, "")
    end
  end

  def language_trending_url
    "https://github.com/trending/#{language_class}"
  end

  def no_language?
    (language || "").strip.empty?
  end

  def description_too_short?
    (description.length < 5) || (description.split(" ").length < 3)
  end

  def description_too_long?
    description.length > 280
  end

  # Short blocklist entries ("ass", "ho", "kill") sit inside everyday words
  # ("assistant", "Python", "skills"), so they only count as a token of their
  # own. Longer entries still match anywhere, which catches compounds like
  # "NiggerFoundation".
  def obscene?
    [description, name, owner.login].any? { |text| obscene_text? text.to_s }
  end

  def malware?
    [description, name].any?(&:malware?) ||
      description.downcase.near_match?(name.downcase)
  end

  def too_many_new_stars?
    new_stargazers_count > stargazers_count
  end

  private

  def obscene_text? text
    blocked_words.any? { |blocked|
      if blocked.length >= OBSCENITY_SUBSTRING_MIN
        !!(text =~ /#{Regexp.escape blocked}/i)
      else
        token_in? text, blocked
      end
    }
  end

  # A token is delimited by anything that isn't a letter ("91porn",
  # "my_porn_site") or by a camelCase hump ("techGay").
  def token_in? text, word
    pattern = /#{Regexp.escape word}/i
    position = 0

    while (match = pattern.match text, position)
      from, to = match.begin(0), match.end(0)
      return true if token_start?(text, from) && token_end?(text, to)
      position = from + 1
    end

    false
  end

  def token_start? text, from
    from == 0 ||
      text[from - 1] !~ /[[:alpha:]]/ ||
      (text[from - 1] =~ /[[:lower:]]/ && text[from] =~ /[[:upper:]]/)
  end

  def token_end? text, to
    to == text.length ||
      text[to] !~ /[[:alpha:]]/ ||
      (text[to - 1] =~ /[[:lower:]]/ && text[to] =~ /[[:upper:]]/)
  end

  def blocked_github_repo_ids
    [156648725]
  end

  def blocked_github_user_ids
    [34570255, 48942249, 114510212]
  end

  def blocked_words
    Obscenity::Base.blacklist + %w(gay porn)
  end
end
