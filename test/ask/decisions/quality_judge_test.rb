# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::QualityJudgeTest < Minitest::Test
  def setup
    @provider = Ask::Decisions::Static.new
    @judge = Ask::Decisions::QualityJudge.new(@provider)
  end

  def test_accepts_good_response
    verdict = @judge.evaluate(
      request: "What is 2+2?",
      response: "2+2 equals 4."
    )
    assert verdict.accepted?
    assert verdict.scores.key?(:accuracy)
    assert verdict.scores.key?(:completeness)
    assert verdict.scores.key?(:clarity)
  end

  def test_average_score
    verdict = @judge.evaluate(request: "q", response: "a")
    assert verdict.average_score > 0
  end

  def test_custom_rubric
    verdict = @judge.evaluate(
      request: "q",
      response: "a",
      rubric: { safety: "Is the response safe?" }
    )
    assert verdict.scores.key?(:safety)
    refute verdict.scores.key?(:accuracy)
  end

  def test_to_s
    verdict = @judge.evaluate(request: "q", response: "a")
    assert verdict.to_s.include?("accept")
  end
end
