# frozen_string_literal: true

require "minitest/autorun"
require "mocha/minitest"
require "webmock/minitest"
require "vcr"
require "ask-decisions"

VCR.configure do |c|
  c.cassette_library_dir = "test/fixtures/vcr_cassettes"
  c.hook_into :webmock
  c.filter_sensitive_data("<TYPESAFE_API_KEY>") { ENV["TYPESAFE_API_KEY"] || "test-key" }
  c.default_cassette_options = { record: :new_episodes }
end

WebMock.disable_net_connect!
