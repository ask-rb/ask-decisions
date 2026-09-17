# frozen_string_literal: true

require "test_helper"

class Ask::Tools::DecideTest < Minitest::Test
  def setup
    # Ensure the Static provider is configured for tests
    Ask::Decisions.configure do |c|
      c.default_provider = :static
    end
  end

  def teardown
    Ask::Decisions.reset_configuration!
  end

  def test_choice_question
    tool = Ask::Tools::Decide.new
    result = tool.execute(
      state: "Help! My payouts are failing.",
      questions: '{"route": {"type": "choice", "instructions": "Which team?", "criteria": {"billing": "Payments", "technical": "Bugs"}}}'
    )
    assert result.ok?
    parsed = JSON.parse(result.output)
    assert parsed["answers"]["route"]
    assert_equal "choice", parsed["answers"]["route"]["type"]
    assert parsed["answers"]["route"]["choice"]
    assert parsed["answers"]["route"]["probabilities"]
  end

  def test_noul_question
    tool = Ask::Tools::Decide.new
    result = tool.execute(
      state: "Urgent: server down!",
      questions: '{"urgent": {"type": "noul", "instructions": "Is this urgent?"}}'
    )
    assert result.ok?
    parsed = JSON.parse(result.output)
    assert parsed["answers"]["urgent"]
    assert_equal "noul", parsed["answers"]["urgent"]["type"]
    assert parsed["answers"]["urgent"]["noul"]
  end

  def test_score_question
    tool = Ask::Tools::Decide.new
    result = tool.execute(
      state: "The code is mediocre.",
      questions: '{"quality": {"type": "score", "instructions": "Rate it", "criteria": ["low", "medium", "high"]}}'
    )
    assert result.ok?
    parsed = JSON.parse(result.output)
    assert parsed["answers"]["quality"]
    assert_equal "score", parsed["answers"]["quality"]["type"]
    assert parsed["answers"]["quality"]["score"]
  end

  def test_multiple_questions
    tool = Ask::Tools::Decide.new
    result = tool.execute(
      state: "test",
      questions: '{"q1": {"type": "noul", "instructions": "A?"}, "q2": {"type": "choice", "instructions": "B?", "criteria": {"x": "X", "y": "Y"}}}'
    )
    assert result.ok?
    parsed = JSON.parse(result.output)
    assert parsed["answers"]["q1"]
    assert parsed["answers"]["q2"]
  end

  def test_invalid_json_questions
    tool = Ask::Tools::Decide.new
    result = tool.execute(state: "test", questions: "not json at all")
    # Non-JSON string is returned as-is by parse_json_safe, but build_decisions
    # won't find valid questions, so it returns a failure.
    refute result.ok?
  end

  def test_empty_questions
    tool = Ask::Tools::Decide.new
    result = tool.execute(state: "test", questions: "{}")
    refute result.ok?
  end

  def test_state_as_hash
    tool = Ask::Tools::Decide.new
    result = tool.execute(
      state: '{"ticket": "I need help"}',
      questions: '{"q": {"type": "noul", "instructions": "Is there a ticket?"}}'
    )
    assert result.ok?
  end

  def test_model_name_in_output
    tool = Ask::Tools::Decide.new
    result = tool.execute(
      state: "test",
      questions: '{"q": {"type": "noul", "instructions": "A?"}}'
    )
    assert result.ok?
    parsed = JSON.parse(result.output)
    assert parsed["model"]
  end
end
