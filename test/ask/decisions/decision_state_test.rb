# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::DecisionStateTest < Minitest::Test
  def test_basic_state
    state = Ask::Decisions::DecisionState.build(
      user_turn: "check the weather in seattle"
    )
    assert_equal "check the weather in seattle", state[:user_turn]
  end

  def test_includes_tools
    state = Ask::Decisions::DecisionState.build(
      user_turn: "run tests",
      tools: [
        { name: "bash", description: "Run a shell command" },
        { name: "read", description: "Read a file" }
      ]
    )
    assert state[:available_tools]
    assert state[:available_tools].any? { |t| t.include?("bash") }
  end

  def test_includes_recent_turns
    state = Ask::Decisions::DecisionState.build(
      user_turn: "continue",
      recent_turns: [
        { role: "user", content: "help me" },
        { role: "assistant", content: "sure, what do you need?" }
      ]
    )
    assert state[:recent_turns]
    assert_equal 2, state[:recent_turns].size
  end

  def test_includes_plan
    state = Ask::Decisions::DecisionState.build(
      user_turn: "do it",
      plan: "Step 1: investigate. Step 2: fix."
    )
    assert state[:plan].include?("investigate")
  end

  def test_includes_memory
    state = Ask::Decisions::DecisionState.build(
      user_turn: "hello",
      memory: ["User prefers dark mode", "Project uses Ruby 3.2"]
    )
    assert state[:memory]
    assert_equal 2, state[:memory].size
  end

  def test_budget_truncation
    long_turn = "x" * 100_000
    state = Ask::Decisions::DecisionState.build(
      user_turn: long_turn,
      budget: 1000
    )
    assert state[:user_turn].length < 1000
    assert state[:user_turn].include?("elided")
  end

  def test_recent_turns_truncation
    turns = (1..100).map { |i| { role: "user", content: "message #{i} " + "y" * 500 } }
    state = Ask::Decisions::DecisionState.build(
      user_turn: "test",
      recent_turns: turns,
      budget: 5000
    )
    # Should keep some but not all messages
    assert state[:recent_turns].size < 100
  end

  def test_tools_truncation
    tools = (1..50).map { |i| { name: "tool_#{i}", description: "Tool #{i} " + "z" * 100 } }
    state = Ask::Decisions::DecisionState.build(
      user_turn: "test",
      tools: tools,
      budget: 2000
    )
    assert state[:available_tools]
  end

  def test_truncate_method
    assert_equal "hello", Ask::Decisions::DecisionState.truncate("hello", 10)
    result = Ask::Decisions::DecisionState.truncate("hello world this is long", 10)
    # The truncated result is shorter than the original but may exceed the limit
    # due to the "…[N chars elided]" suffix — that's intentional.
    assert result.length < "hello world this is long".length
    assert result.include?("elided")
  end

  def test_truncate_nil
    assert_equal "", Ask::Decisions::DecisionState.truncate(nil, 10)
  end
end
