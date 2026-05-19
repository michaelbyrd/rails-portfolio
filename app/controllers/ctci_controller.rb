require 'open-uri'

class CtciController < ApplicationController
  layout 'ctci'

  GITHUB_BASE    = "https://github.com/michaelbyrd/CTCI/blob/main"
  GITHUB_RAW     = "https://raw.githubusercontent.com/michaelbyrd/CTCI/main"
  DATA_DIR       = Rails.root.join('config', 'ctci')
  CACHE_DURATION = 1.hour

  def index
    @chapters = load_all_chapters
  end

  def show
    number = params[:chapter].to_i
    path   = DATA_DIR.join("chapter_#{number.to_s.rjust(2, '0')}.rb")
    raise ActionController::RoutingError, "Chapter not found" unless path.exist?

    @chapter = load_chapter(path)
    @chapter[:problems].each do |problem|
      problem[:content] = fetch_content(problem[:github_path])
    end

    @github_base = GITHUB_BASE
  end

  private

  def load_all_chapters
    DATA_DIR.glob('chapter_*.rb').sort.map { |f| load_chapter(f) }
  end

  def load_chapter(path)
    eval(path.read, binding, path.to_s) # rubocop:disable Security/Eval
  end

  def fetch_content(github_path)
    Rails.cache.fetch("ctci/#{github_path}", expires_in: CACHE_DURATION) do
      URI.open("#{GITHUB_RAW}/#{github_path}").read
    end
  end
end