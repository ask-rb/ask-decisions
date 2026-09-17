# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::StaticTest < Minitest::Test
  def test_returns_canned_choice
    canned = Ask::DecisionResult::ChoiceAnswer.new(
      id: "route", choice: "billing", probabilities: { "billing" => 1.0 }, confidence: 1.0
    )
    provider = Ask::Decisions::Static.new(answers: { "route" => canned })

    q = Ask::Decision::Choice.new(instructions: "Which team?", criteria: { billing: "...", technical: "..." })
    result = provider.evaluate(state: "test", decisions: { "route" => q })

    assert_equal "billing", result["route"].choice
  end

  def test_default_answer_for_choice
    provider = Ask::Decisions::Static.new
    q = Ask::Decision::Choice.new(instructions: "Which team?", criteria: { a: "A", b: "B" })
    result = provider.evaluate(state: "test", decisions: { "q" => q })

    assert result["q"].choice
    assert result["q"].probabilities
    assert_in_delta 1.0, result["q"].confidence, 0.001
  end

  def test_default_answer_for_noul
    provider = Ask::Decisions::Static.new
    q = Ask::Decision::Noul.new(instructions: "Is it urgent?")
    result = provider.evaluate(state: "test", decisions: { "q" => q })

    assert_in_delta 0.5, result["q"].noul, 0.001
  end

  def test_default_answer_for_score
    provider = Ask::Decisions::Static.new
    q = Ask::Decision::Score.new(instructions: "Rate it", criteria: ["low", "high"])
    result = provider.evaluate(state: "test", decisions: { "q" => q })

    assert result["q"].score
    assert result["q"].legend
  end

  def test_model_name
    provider = Ask::Decisions::Static.new
    q = Ask::Decision::Noul.new(instructions: "q")
    result = provider.evaluate(state: "test", decisions: { "q" => q })

    assert_equal "static", result.model
  end
end
