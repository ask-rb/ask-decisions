# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::OutputJudgeTest < Minitest::Test
  def setup
    @provider = Ask::Decisions::Static.new
    @judge = Ask::Decisions::OutputJudge.new(@provider)
  end

  def test_clean_output
    result = @judge.judge(
      tool: "bash",
      output: "On branch main\nnothing to commit",
      args: { command: "git status" }
    )
    refute result.leak?
    assert_equal "no_failure", result.failure_class
    refute result.failure?
    assert_equal "clean", result.to_s
  end

  def test_secret_detected
    provider = Ask::Decisions::Static.new(answers: {
      "leaks_secret" => Ask::DecisionResult::NoulAnswer.new(id: "leaks_secret", noul: 0.95),
      "failure_class" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "failure_class", choice: "no_failure",
        probabilities: { "no_failure" => 1.0 }, confidence: 0.9
      )
    })
    judge = Ask::Decisions::OutputJudge.new(provider)
    result = judge.judge(tool: "bash", output: "AWS_SECRET_KEY=AKIA1234567890", args: {})

    assert result.leak?
    assert result.to_s.include?("LEAK")
  end

  def test_failure_classification
    provider = Ask::Decisions::Static.new(answers: {
      "leaks_secret" => Ask::DecisionResult::NoulAnswer.new(id: "leaks_secret", noul: 0.01),
      "failure_class" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "failure_class", choice: "transient",
        probabilities: { "transient" => 1.0 }, confidence: 0.95
      )
    })
    judge = Ask::Decisions::OutputJudge.new(provider)
    result = judge.judge(tool: "bash", output: "npm ERR! code ECONNRESET", args: {})

    assert result.failure?
    assert_equal "transient", result.failure_class
    assert_equal "Retry unchanged.", result.advice
  end

  def test_code_bug_classification
    provider = Ask::Decisions::Static.new(answers: {
      "leaks_secret" => Ask::DecisionResult::NoulAnswer.new(id: "leaks_secret", noul: 0.01),
      "failure_class" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "failure_class", choice: "code_bug",
        probabilities: { "code_bug" => 1.0 }, confidence: 1.0
      )
    })
    judge = Ask::Decisions::OutputJudge.new(provider)
    result = judge.judge(tool: "bash", output: "error TS2322: Type 'string' is not assignable", args: {})

    assert result.failure?
    assert_equal "code_bug", result.failure_class
    assert result.advice.include?("must change")
  end

  def test_tool_not_judged
    result = @judge.judge(tool: "read", output: "contents", args: {})
    refute result.leak?
    assert_equal "no_failure", result.failure_class
  end

  def test_output_truncation
    long_output = "x" * 5000
    judge = Ask::Decisions::OutputJudge.new(@provider, output_limit: 1000)
    # Should not raise
    result = judge.judge(tool: "bash", output: long_output, args: {})
    assert result
  end

  def test_all_advice_classes_covered
    Ask::Decisions::OutputJudge::ADVICE.each_key do |klass|
      assert Ask::Decisions::OutputJudge::ADVICE.key?(klass),
        "Missing advice for failure class: #{klass}"
    end
    assert_equal 6, Ask::Decisions::OutputJudge::ADVICE.size
  end
end
