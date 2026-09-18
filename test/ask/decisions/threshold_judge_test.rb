# frozen_string_literal: true

require "test_helper"

class ThresholdJudgeTest < Minitest::Test
  def setup
    @provider = Ask::Decisions::Static.new
    @judge = Ask::Decisions::ThresholdJudge.new(@provider)
  end

  def test_returns_verdict_object
    verdict = @judge.evaluate(subject: "test", question: "Is this good?")
    assert_kind_of Ask::Decisions::ThresholdJudge::ThresholdVerdict, verdict
  end

  def test_verdict_has_noul
    verdict = @judge.evaluate(subject: "test", question: "Is this good?")
    assert_kind_of Float, verdict.noul
    assert verdict.noul.between?(0.0, 1.0)
  end

  def test_verdict_has_confidence
    verdict = @judge.evaluate(subject: "test", question: "Is this good?")
    assert_kind_of Float, verdict.confidence
    assert verdict.confidence.between?(0.0, 0.5)
  end

  def test_verdict_has_threshold
    verdict = @judge.evaluate(subject: "test", question: "Is this good?", threshold: 0.8)
    assert_equal 0.8, verdict.threshold
  end

  def test_verdict_passed_when_above_threshold
    # Static provider returns noul=0.5, threshold=0.4 → passes
    verdict = @judge.evaluate(subject: "test", question: "Is this good?", threshold: 0.4)
    assert verdict.passed?
  end

  def test_verdict_failed_when_below_threshold
    # Static provider returns noul=0.5, threshold=0.6 → fails
    verdict = @judge.evaluate(subject: "test", question: "Is this good?", threshold: 0.6)
    refute verdict.passed?
  end

  def test_default_threshold_is_0_7
    verdict = @judge.evaluate(subject: "test", question: "Is this good?")
    assert_equal 0.7, verdict.threshold
  end

  def test_to_s_includes_status_and_values
    verdict = @judge.evaluate(subject: "test", question: "Is this good?")
    str = verdict.to_s
    assert_includes str, "noul:"
    assert_includes str, "confidence:"
  end

  def test_with_custom_provider_answers
    provider = Ask::Decisions::Static.new(
      answers: { "verdict" => Ask::DecisionResult::NoulAnswer.new(id: "verdict", noul: 0.9) }
    )
    judge = Ask::Decisions::ThresholdJudge.new(provider)
    verdict = judge.evaluate(subject: "test", question: "Is this good?")
    assert_equal 0.9, verdict.noul
    assert verdict.passed?
  end
end
