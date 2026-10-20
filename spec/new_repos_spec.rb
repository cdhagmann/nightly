require "date"
require_relative "../lib/new_repos"

RSpec.describe NewRepos do
  let(:day) { Date.new 2026, 10, 19 }
  let(:github) { double "github" }
  let(:new_repos) { NewRepos.new day, github }

  def item name, attrs={}
    {
      "id" => name.hash.abs,
      "name" => name,
      "full_name" => "someone/#{name}",
      "url" => "https://api.github.com/repos/someone/#{name}",
      "html_url" => "https://github.com/someone/#{name}",
      "description" => "A perfectly fine project",
      "stargazers_count" => 100,
      "size" => 5000,
      "language" => "Ruby",
      "topics" => [],
      "owner" => {"id" => 1, "login" => "someone"}
    }.merge(attrs)
  end

  def search_returns *items
    allow(github).to receive(:search_repositories).and_return items
  end

  before { allow($stderr).to receive(:puts) } # skip lines are asserted in one example below

  describe "#top" do
    it "searches for repos created that day with at least ten stars" do
      expect(github).to receive(:search_repositories).with("created:2026-10-19 stars:>=10", 3).and_return []
      expect(new_repos.top).to eq []
    end

    it "keeps the order stars gave them, up to the limit" do
      search_returns item("a", "stargazers_count" => 90), item("b", "stargazers_count" => 80), item("c")
      expect(new_repos.top(2).map(&:name)).to eq %w(a b)
    end

    it "counts all of a new repo's stars as new stars" do
      search_returns item("a", "stargazers_count" => 42)
      repo = new_repos.top.first

      expect(repo.new_stargazers_count).to eq 42
      expect(repo).not_to be_too_many_new_stars
    end

    it "escapes descriptions for the email" do
      search_returns item("a", "description" => "Use <script> & more")
      expect(new_repos.top.first.description).to eq "Use &lt;script&gt; &amp; more"
    end

    it "skips repos the shared checks reject, and says why" do
      search_returns item("tiny", "description" => "x"), item("fine")

      expect(new_repos.top.map(&:name)).to eq %w(fine)
      expect { new_repos.top }.to output(
        %r{skipped https://github.com/someone/tiny \(100 stars\): description too short}
      ).to_stderr
    end

    it "skips repos whose owner or name is on the malware list" do
      search_returns item("tool", "url" => "https://api.github.com/repos/free-cheats/tool"), item("fine")
      expect(new_repos.top.map(&:name)).to eq %w(fine)
    end

    it "copes with a day that has nothing" do
      search_returns
      expect(new_repos.top).to eq []
    end
  end
end
