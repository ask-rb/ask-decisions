# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::FailureClassifierTest < Minitest::Test
  def setup
    @provider = Ask::Decisions::Static.new
  end

  def test_no_failure
    classifier = Ask::Decisions::FailureClassifier.new(@provider)
    result = classifier.classify(tool: "bash", output: "OK", attempt: 1)
    assert_equal "no_failure", result.failure_class
    refute result.retryable?
    assert result.give_up?
  end

  def test_transient_retryable
    provider = Ask::Decisions::Static.new(answers: {
      "leaks_secret" => Ask::DecisionResult::NoulAnswer.new(id: "leaks_secret", noul: 0.01),
      "failure_class" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "failure_class", choice: "transient",
        probabilities: { "transient" => 1.0 }, confidence: 0.95
      )
    })
    classifier = Ask::Decisions::FailureClassifier.new(provider)
    result = classifier.classify(tool: "bash", output: "ECONNRESET", attempt: 1)

    assert result.retryable?
    assert result.should_retry?
    refute result.give_up?
    assert_equal "Retry unchanged.", result.advice
  end

  def test_exhausted_retries
    provider = Ask::Decisions::Static.new(answers: {
      "leaks_secret" => Ask::DecisionResult::NoulAnswer.new(id: "leaks_secret", noul: 0.01),
      "failure_class" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "failure_class", choice: "transient",
        probabilities: { "transient" => 1.0 }, confidence: 0.95
      )
    })
    classifier = Ask::Decisions::FailureClassifier.new(provider, max_retries: 2)
    result = classifier.classify(tool: "bash", output: "ECONNRESET", attempt: 2)

    assert result.retryable?
    refute result.should_retry?
    assert result.give_up?
  end

  def test_code_bug_not_retryable
    provider = Ask::Decisions::Static.new(answers: {
      "leaks_secret" => Ask::DecisionResult::NoulAnswer.new(id: "leaks_secret", noul: 0.01),
      "failure_class" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "failure_class", choice: "code_bug",
        probabilities: { "code_bug" => 1.0 }, confidence: 1.0
      )
    })
    classifier = Ask::Decisions::FailureClassifier.new(provider)
    result = classifier.classify(tool: "bash", output: "TS2322", attempt: 1)

    refute result.retryable?
    assert result.give_up?
  end

  def test_leak_detected
    provider = Ask::Decisions::Static.new(answers: {
      "leaks_secret" => Ask::DecisionResult::NoulAnswer.new(id: "leaks_secret", noul: 0.95),
      "failure_class" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "failure_class", choice: "no_failure",
        probabilities: { "no_failure" => 1.0 }, confidence: 0.9
      )
    })
    classifier = Ask::Decisions::FailureClassifier.new(provider)
    result = classifier.classify(tool: "bash", output: "AWS_SECRET=...", attempt: 1)

    assert result.leak?
    refute result.retryable?
  end

  def test_to_s
    classifier = Ask::Decisions::FailureClassifier.new(@provider)
    result = classifier.classify(tool: "bash", output: "OK", attempt: 1)
    assert_equal "no failure", result.to_s
  end
end
