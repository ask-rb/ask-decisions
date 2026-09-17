# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::LoopDetectorTest < Minitest::Test
  def test_no_loop
    provider = Ask::Decisions::Static.new(answers: {
      "repeating" => Ask::DecisionResult::NoulAnswer.new(id: "repeating", noul: 0.1),
      "stuck" => Ask::DecisionResult::NoulAnswer.new(id: "stuck", noul: 0.1),
      "progress" => Ask::DecisionResult::ScoreAnswer.new(
        id: "progress", score: 3.0,
        legend: { "0" => "None", "1" => "Minimal", "2" => "Some", "3" => "Significant", "4" => "Complete" },
        probabilities: { "3" => 1.0 }, confidence: 0.9
      )
    })
    detector = Ask::Decisions::LoopDetector.new(provider)
    verdict = detector.check(recent_turns: [], turn_count: 3)

    refute verdict.repeating?
    refute verdict.stuck?
    assert verdict.progressing?
    assert_equal "continue", verdict.advice
  end

  def test_repeating_and_stuck
    provider = Ask::Decisions::Static.new(answers: {
      "repeating" => Ask::DecisionResult::NoulAnswer.new(id: "repeating", noul: 0.9),
      "stuck" => Ask::DecisionResult::NoulAnswer.new(id: "stuck", noul: 0.85),
      "progress" => Ask::DecisionResult::ScoreAnswer.new(
        id: "progress", score: 0.5,
        legend: { "0" => "None", "1" => "Minimal" },
        probabilities: { "0" => 0.8, "1" => 0.2 }, confidence: 0.8
      )
    })
    detector = Ask::Decisions::LoopDetector.new(provider)
    verdict = detector.check(
      recent_turns: [
        { role: "assistant", tool_calls: [{ name: "bash", arguments: { command: "npm test" } }] },
        { role: "assistant", tool_calls: [{ name: "bash", arguments: { command: "npm test" } }] }
      ],
      turn_count: 10
    )

    assert verdict.repeating?
    assert verdict.stuck?
    refute verdict.progressing?
    assert_equal "stop", verdict.advice
  end

  def test_stuck_but_not_repeating
    provider = Ask::Decisions::Static.new(answers: {
      "repeating" => Ask::DecisionResult::NoulAnswer.new(id: "repeating", noul: 0.2),
      "stuck" => Ask::DecisionResult::NoulAnswer.new(id: "stuck", noul: 0.8),
      "progress" => Ask::DecisionResult::ScoreAnswer.new(
        id: "progress", score: 1.0,
        legend: { "0" => "None", "1" => "Minimal" },
        probabilities: { "1" => 1.0 }, confidence: 0.9
      )
    })
    detector = Ask::Decisions::LoopDetector.new(provider)
    verdict = detector.check(recent_turns: [], turn_count: 5)

    refute verdict.repeating?
    assert verdict.stuck?
    assert_equal "pivot", verdict.advice
  end

  def test_extract_actions
    detector = Ask::Decisions::LoopDetector.new(Ask::Decisions::Static.new)
    turns = [
      { role: "assistant", tool_calls: [{ name: "bash", arguments: { command: "ls" } }] },
      { role: "assistant", tool_calls: [{ name: "read", arguments: { path: "/etc/hosts" } }] }
    ]
    verdict = detector.check(recent_turns: turns, turn_count: 2)
    assert verdict
  end

  def test_to_s
    provider = Ask::Decisions::Static.new(answers: {
      "repeating" => Ask::DecisionResult::NoulAnswer.new(id: "repeating", noul: 0.1),
      "stuck" => Ask::DecisionResult::NoulAnswer.new(id: "stuck", noul: 0.1),
      "progress" => Ask::DecisionResult::ScoreAnswer.new(
        id: "progress", score: 3.0,
        legend: { "0" => "None", "1" => "Minimal", "2" => "Some", "3" => "Significant" },
        probabilities: { "3" => 1.0 }, confidence: 0.9
      )
    })
    detector = Ask::Decisions::LoopDetector.new(provider)
    verdict = detector.check(recent_turns: [], turn_count: 1)
    assert verdict.to_s.include?("continue")
  end
end
