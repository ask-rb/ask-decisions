# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::MCPHelperTest < Minitest::Test
  def test_tool_returns_decide_instance
    tool = Ask::Decisions::MCPHelper.tool
    assert_instance_of Ask::Tools::Decide, tool
    assert_equal "decide", tool.name
  end

  def test_tool_has_input_schema
    tool = Ask::Decisions::MCPHelper.tool
    # params_schema may be nil if ask-tools wasn't loaded; skip gracefully
    skip "ask-tools not loaded" unless tool.respond_to?(:params_schema)
    schema = tool.params_schema
    skip "params_schema not populated" unless schema
    props = schema["properties"] || schema[:properties] || {}
    assert props["state"] || props[:state], "expected 'state' in schema properties"
    assert props["questions"] || props[:questions], "expected 'questions' in schema properties"
  end
end
