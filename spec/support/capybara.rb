require 'capybara/cuprite'

CHROME_PATH = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size:      [1280, 800],
    browser_path:     CHROME_PATH,
    browser_options:  { 'no-sandbox': nil },
    headless:         true,
    process_timeout:  20,
    timeout:          10
  )
end

Capybara.default_driver    = :rack_test
Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5
Capybara.server = :puma, { Silent: true }

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :cuprite
  end
end
