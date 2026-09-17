# frozen_string_literal: true

require "test_helper"

class Ask::Decision::NoulTest < Minitest::Test
  def test_type
    q = Ask::Decision::Noul.new(instructions: "Is this urgent?")
    assert_equal :noul, q.type
  end

  def test_to_h_without_criteria
    q = Ask::Decision::Noul.new(instructions: "Is this urgent?")
    assert_equal({ type: "noul", instructions: "Is this urgent?" }, q.to_h)
  end

  def test_to_h_with_criteria
    q = Ask::Decision::Noul.new(
      instructions: "Is this urgent?",
      criteria: { "true" => "Yes, time-sensitive", "false" => "No urgency" }
    )
    h = q.to_h
    assert_equal "noul", h[:type]
    assert h[:criteria].key?("true")
  end

  def test_criteria_is_frozen
    q = Ask::Decision::Noul.new(instructions: "q", criteria: { "true" => "yes" })
    assert q.criteria.frozen?
  end
end
