# frozen_string_literal: true

require "test_helper"

class Ask::Decision::ScoreTest < Minitest::Test
  def test_type
    q = Ask::Decision::Score.new(
      instructions: "How frustrated?",
      criteria: ["Calm", "Frustrated", "Very angry"]
    )
    assert_equal :score, q.type
  end

  def test_to_h
    q = Ask::Decision::Score.new(
      instructions: "How frustrated?",
      criteria: ["Calm", "Frustrated"]
    )
    assert_equal "score", q.to_h[:type]
    assert_equal ["Calm", "Frustrated"], q.to_h[:criteria]
  end

  def test_requires_at_least_two_levels
    assert_raises(ArgumentError) do
      Ask::Decision::Score.new(instructions: "q", criteria: ["only one"])
    end
  end

  def test_criteria_is_frozen
    q = Ask::Decision::Score.new(instructions: "q", criteria: ["a", "b"])
    assert q.criteria.frozen?
  end
end
