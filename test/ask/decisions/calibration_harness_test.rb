# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::CalibrationHarnessTest < Minitest::Test
  def setup
    @provider = Ask::Decisions::Static.new
  end

  def test_runs_single_case
    harness = Ask::Decisions::CalibrationHarness.new(@provider)
    harness.add_case(
      id: "urgent",
      state: "Help!",
      decisions: { "urgent" => Ask::Decision::Noul.new(instructions: "Is this urgent?") },
      expected: { "urgent" => { noul_above: 0.3 } }
    )
    summary = harness.run
    assert_equal 1, summary.total
  end

  def test_runs_multiple_cases
    harness = Ask::Decisions::CalibrationHarness.new(@provider)
    harness.add_case(id: "a", state: "x", decisions: { "q" => Ask::Decision::Noul.new(instructions: "A?") })
    harness.add_case(id: "b", state: "y", decisions: { "q" => Ask::Decision::Noul.new(instructions: "B?") })
    summary = harness.run
    assert_equal 2, summary.total
  end

  def test_runs_with_repetition
    harness = Ask::Decisions::CalibrationHarness.new(@provider)
    harness.add_case(
      id: "repeat",
      state: "test",
      decisions: { "q" => Ask::Decision::Noul.new(instructions: "Q?") },
      runs: 3
    )
    summary = harness.run
    assert_equal 3, summary.total
  end

  def test_choice_expectation
    harness = Ask::Decisions::CalibrationHarness.new(@provider)
    harness.add_case(
      id: "route",
      state: "test",
      decisions: { "route" => Ask::Decision::Choice.new(instructions: "Which?", criteria: { a: "A", b: "B" }) },
      expected: { "route" => { choice_is: "a" } }  # Static returns first key
    )
    summary = harness.run
    assert_equal 1, summary.total
  end
end
