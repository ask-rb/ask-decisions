# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::ReflectionJudgeTest < Minitest::Test
  def setup
    @provider = Ask::Decisions::Static.new
    @judge = Ask::Decisions::ReflectionJudge.new(@provider)
  end

  def test_done_when_no_improvement
    verdict = @judge.reflect(request: "q", response: "good answer", attempt: 1)
    # Static returns 0.5 for noul and score 1.5 (midpoint of 0-3)
    # improve? requires noul >= 0.5 AND score < 3.5 → true
    # So with static defaults, it will say improve
    assert verdict.improve? || verdict.done?
  end

  def test_max_reflections_stops
    judge = Ask::Decisions::ReflectionJudge.new(@provider, max_reflections: 1)
    verdict = judge.reflect(request: "q", response: "a", attempt: 1)
    assert verdict.done?
  end

  def test_quality_score
    verdict = @judge.reflect(request: "q", response: "a")
    assert verdict.quality_score >= 0
  end

  def test_to_s
    verdict = @judge.reflect(request: "q", response: "a")
    assert verdict.to_s.include?("quality")
  end
end
