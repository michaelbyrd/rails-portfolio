require 'open-uri'

class CtciController < ApplicationController
  layout 'ctci'

  GITHUB_BASE    = "https://github.com/michaelbyrd/CTCI"
  GITHUB_RAW     = "https://raw.githubusercontent.com/michaelbyrd/CTCI/main"
  CACHE_DURATION = 1.hour

  def index
    @readme_markdown = fetch_readme_markdown
    @github_url      = GITHUB_BASE
  end

  private

  def fetch_readme_markdown
    Rails.cache.fetch("ctci/readme_markdown", expires_in: CACHE_DURATION) do
      URI.open("#{GITHUB_RAW}/README.md").read.force_encoding("UTF-8")
    end
  end
end