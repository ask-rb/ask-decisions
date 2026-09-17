# frozen_string_literal: true

require "test_helper"

class Ask::Decision::ChoiceTest < Minitest::Test
  def test_type
    q = Ask::Decision::Choice.new(
      instructions: "Which team?",
      criteria: { billing: "Payments", technical: "Bugs" }
    )
    assert_equal :choice, q.type
  end

  def test_to_h
    q = Ask::Decision::Choice.new(
      instructions: "Which team?",
      criteria: { billing: "Payments", technical: "Bugs" }
    )
    expected = {
      type: "choice",
      instructions: "Which team?",
      criteria: { billing: "Payments", technical: "Bugs" }
    }
    assert_equal expected, q.to_h
  end

  def test_criteria_is_frozen
    q = Ask::Decision::Choice.new(instructions: "q", criteria: { a: "b" })
    assert q.criteria.frozen?
  end
end
