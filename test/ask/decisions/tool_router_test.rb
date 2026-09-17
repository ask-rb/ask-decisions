# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::ToolRouterTest < Minitest::Test
  TOOLS = [
    { name: "bash", description: "Run a shell command" },
    { name: "read", description: "Read a file" },
    { name: "web_search", description: "Search the web" }
  ].freeze

  def test_routes_to_tool
    provider = Ask::Decisions::Static.new(answers: {
      "tool.route" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "tool.route", choice: "bash",
        probabilities: { "bash" => 0.9, "read" => 0.05, "web_search" => 0.05,
                         "answer_directly" => 0.0, "ask_clarifying_question" => 0.0, "none" => 0.0 },
        confidence: 0.9
      )
    })
    router = Ask::Decisions::ToolRouter.new(provider, tools: TOOLS)
    result = router.route(user_turn: "run the tests")

    assert result.call_tool?
    assert_equal "bash", result.tool
    assert result.confident?(0.5)
  end

  def test_routes_to_answer_directly
    provider = Ask::Decisions::Static.new(answers: {
      "tool.route" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "tool.route", choice: "answer_directly",
        probabilities: { "answer_directly" => 0.8, "bash" => 0.2 },
        confidence: 0.8
      )
    })
    router = Ask::Decisions::ToolRouter.new(provider, tools: TOOLS)
    result = router.route(user_turn: "what is 2+2?")

    assert result.answer_directly?
    refute result.call_tool?
  end

  def test_routes_to_none
    provider = Ask::Decisions::Static.new(answers: {
      "tool.route" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "tool.route", choice: "none",
        probabilities: { "none" => 0.9, "bash" => 0.1 },
        confidence: 0.9
      )
    })
    router = Ask::Decisions::ToolRouter.new(provider, tools: TOOLS)
    result = router.route(user_turn: "thanks")

    assert result.no_action?
  end

  def test_fallback_on_low_confidence
    provider = Ask::Decisions::Static.new(answers: {
      "tool.route" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "tool.route", choice: "bash",
        probabilities: { "bash" => 0.4, "read" => 0.3, "web_search" => 0.3 },
        confidence: 0.4
      )
    })
    router = Ask::Decisions::ToolRouter.new(provider, tools: TOOLS, none_threshold: 0.5)
    result = router.route(user_turn: "do the thing")

    assert result.fallback?
  end

  def test_to_s
    provider = Ask::Decisions::Static.new(answers: {
      "tool.route" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "tool.route", choice: "bash",
        probabilities: { "bash" => 1.0 },
        confidence: 0.95
      )
    })
    router = Ask::Decisions::ToolRouter.new(provider, tools: TOOLS)
    result = router.route(user_turn: "run tests")
    assert result.to_s.include?("bash")
  end

  def test_non_tool_outcomes_included_in_criteria
    provider = Ask::Decisions::Static.new
    router = Ask::Decisions::ToolRouter.new(provider, tools: TOOLS)
    result = router.route(user_turn: "hello")

    # Static provider returns the first criterion by default, which should
    # include the non-tool outcomes.
    assert result.tool
  end
end
