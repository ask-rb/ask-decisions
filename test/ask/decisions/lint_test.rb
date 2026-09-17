# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::LintTest < Minitest::Test
  def test_clean_question
    q = Ask::Decision::Choice.new(
      instructions: "Which team?",
      criteria: { billing: "Payments", technical: "Bugs", none: "None of the above" }
    )
    warnings = Ask::Decisions::Lint.check({ "q" => q })
    assert_empty warnings
  end

  def test_reasoning_path_detected
    q = Ask::Decision::Noul.new(
      instructions: "Is this destructive, since it cannot be recovered from version control?"
    )
    warnings = Ask::Decisions::Lint.check({ "q" => q })
    assert warnings.any? { |w| w.include?("reasoning path") }
  end

  def test_counting_detected
    q = Ask::Decision::Noul.new(
      instructions: "How many items are in this list?"
    )
    warnings = Ask::Decisions::Lint.check({ "q" => q })
    assert warnings.any? { |w| w.include?("counting") }
  end

  def test_date_comparison_detected
    q = Ask::Decision::Noul.new(
      instructions: "Which date comes first?"
    )
    warnings = Ask::Decisions::Lint.check({ "q" => q })
    assert warnings.any? { |w| w.include?("date comparison") }
  end

  def test_missing_none_option
    q = Ask::Decision::Choice.new(
      instructions: "Which team?",
      criteria: { billing: "Payments", technical: "Bugs" }
    )
    warnings = Ask::Decisions::Lint.check({ "q" => q })
    assert warnings.any? { |w| w.include?("none/other") }
  end

end
