# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::ConfidencePolicyTest < Minitest::Test
  def test_high_confidence_acts
    policy = Ask::Decisions::ConfidencePolicy.new
    decision = policy.evaluate(tool: "bash", confidence: 0.9)
    assert decision.act?
  end

  def test_medium_confidence_reviews
    policy = Ask::Decisions::ConfidencePolicy.new
    decision = policy.evaluate(tool: "bash", confidence: 0.6)
    assert decision.review?
  end

  def test_low_confidence_escalates
    policy = Ask::Decisions::ConfidencePolicy.new
    decision = policy.evaluate(tool: "bash", confidence: 0.2)
    assert decision.escalate?
  end

  def test_nil_confidence_escalates
    policy = Ask::Decisions::ConfidencePolicy.new
    decision = policy.evaluate(tool: "bash", confidence: nil)
    assert decision.escalate?
  end

  def test_custom_rule
    policy = Ask::Decisions::ConfidencePolicy.new
    policy.add_rule("rm", risk: :high, act_threshold: 0.95)
    decision = policy.evaluate(tool: "rm", confidence: 0.9)
    assert decision.review?  # below 0.95 act threshold, but above review
  end

  def test_high_risk_needs_higher_confidence
    policy = Ask::Decisions::ConfidencePolicy.new
    policy.add_rule("write", risk: :high)
    decision = policy.evaluate(tool: "write", confidence: 0.8)
    assert decision.review?  # 0.8 < 0.9 act threshold
  end

  def test_low_risk_act_at_lower_threshold
    policy = Ask::Decisions::ConfidencePolicy.new
    policy.add_rule("read", risk: :low)
    decision = policy.evaluate(tool: "read", confidence: 0.6)
    assert decision.act?  # 0.6 > 0.5 act threshold
  end

  def test_default_risk
    policy = Ask::Decisions::ConfidencePolicy.new
    policy.default_risk = :low
    decision = policy.evaluate(tool: "unknown_tool", confidence: 0.6)
    assert decision.act?  # uses default low risk (act at 0.5)
  end

  def test_to_s
    policy = Ask::Decisions::ConfidencePolicy.new
    decision = policy.evaluate(tool: "bash", confidence: 0.9)
    assert decision.to_s.include?("act")
  end

  def test_boundary_at_act_threshold
    policy = Ask::Decisions::ConfidencePolicy.new
    decision = policy.evaluate(tool: "bash", confidence: 0.7)
    assert decision.act?  # exactly at medium act_threshold
  end

  def test_boundary_below_act_threshold
    policy = Ask::Decisions::ConfidencePolicy.new
    decision = policy.evaluate(tool: "bash", confidence: 0.69)
    assert decision.review?  # just below act_threshold
  end
end
