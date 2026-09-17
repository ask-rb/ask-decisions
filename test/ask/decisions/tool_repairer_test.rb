# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::ToolRepairerTest < Minitest::Test
  TOOLS = [
    { name: "bash", description: "Run a shell command" },
    { name: "read", description: "Read a file" }
  ].freeze

  def setup
    @provider = Ask::Decisions::Static.new
    @repairer = Ask::Decisions::ToolRepairer.new(@provider)
  end

  def test_repair_invalid_tool_name
    result = @repairer.repair(
      attempted_tool: "bsh",
      attempted_args: { command: "ls" },
      available_tools: TOOLS
    )
    assert result.repaired?
    assert_includes %w[bash read], result.repaired_tool
  end

  def test_valid_tool_name_repairs_args
    result = @repairer.repair(
      attempted_tool: "bash",
      attempted_args: { command: "ls" },
      available_tools: TOOLS
    )
    assert_equal "bash", result.repaired_tool
    assert result.repaired_args
  end

  def test_to_s
    result = @repairer.repair(
      attempted_tool: "bsh",
      attempted_args: {},
      available_tools: TOOLS
    )
    assert result.to_s.include?("bash") || result.to_s.include?("unrepairable")
  end
end
