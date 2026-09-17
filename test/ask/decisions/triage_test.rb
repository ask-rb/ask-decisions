# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::TriageTest < Minitest::Test
  LANES = {
    "knowledge" => "Asks about the business",
    "booking" => "Wants to book",
    "human" => "Wants a person",
    "unclear" => "None of these is clear"
  }.freeze

  def provider(answers: {})
    Ask::Decisions::Static.new(answers: answers)
  end

  def triage(answers: {})
    Ask::Decisions::Triage.new(provider(answers: answers), lanes: LANES)
  end

  def choice(id, lane, confidence)
    Ask::DecisionResult::ChoiceAnswer.new(
      id: id, choice: lane,
      probabilities: { lane => confidence, "other" => 1.0 - confidence },
      confidence: confidence
    )
  end

  # --- the lane ---

  def test_reads_the_lane
    verdict = triage(answers: {"lane" => choice("lane", "booking", 0.94)})
      .read(message: "I'd like a cleaning on Tuesday")

    assert_equal "booking", verdict.lane
    assert_in_delta 0.94, verdict.confidence
    assert verdict.known?
  end

  def test_certain_at_the_threshold
    verdict = triage(answers: {"lane" => choice("lane", "knowledge", 0.7)})
      .read(message: "are you open sunday")

    assert verdict.certain?(0.7)
    refute verdict.certain?(0.71)
  end

  def test_an_unsure_reading_is_not_certain
    verdict = triage(answers: {"lane" => choice("lane", "knowledge", 0.4)})
      .read(message: "hmm")

    refute verdict.certain?
    assert verdict.known?
  end

  # --- the questions that ride along ---

  def test_reads_sentiment_and_the_want_for_a_human
    answers = {
      "lane" => choice("lane", "human", 0.9),
      "sentiment" => Ask::DecisionResult::ScoreAnswer.new(
        id: "sentiment", score: 0.2, legend: {}, probabilities: {}, confidence: 0.8
      ),
      "wants_human" => Ask::DecisionResult::NoulAnswer.new(id: "wants_human", noul: 0.97)
    }
    verdict = triage(answers: answers).read(message: "I want to speak to a manager")

    assert_in_delta 0.2, verdict.sentiment
    assert verdict.wants_human?
  end

  def test_an_unanswered_want_for_a_human_is_not_a_yes
    verdict = triage(answers: {"lane" => choice("lane", "knowledge", 0.9)})
      .read(message: "what are your hours")

    refute verdict.wants_human?
  end

  # --- what the caller is asked ---

  def test_asks_the_lane_and_both_questions_in_one_request
    seen = nil
    counting = Object.new
    counting.define_singleton_method(:evaluate) do |state:, decisions:, model: nil|
      seen = {state: state, decisions: decisions}
      Ask::DecisionResult::Batch.new(
        answers: {"lane" => Ask::DecisionResult::ChoiceAnswer.new(
          id: "lane", choice: "knowledge", probabilities: {}, confidence: 0.9
        )},
        model: "static"
      )
    end

    Ask::Decisions::Triage.new(counting, lanes: LANES).read(message: "hours?")

    assert_equal %w[lane sentiment wants_human], seen[:decisions].keys.sort
    assert_equal LANES, seen[:decisions]["lane"].criteria
  end

  def test_state_carries_the_message_and_the_context
    seen = nil
    capturing = Object.new
    capturing.define_singleton_method(:evaluate) do |state:, decisions:, model: nil|
      seen = state
      Ask::DecisionResult::Batch.new(
        answers: {"lane" => Ask::DecisionResult::ChoiceAnswer.new(
          id: "lane", choice: "knowledge", probabilities: {}, confidence: 0.9
        )},
        model: "static"
      )
    end

    Ask::Decisions::Triage.new(capturing, lanes: LANES)
      .read(message: "do you deliver?", context: "Writing to Bright Dental")

    assert_equal "do you deliver?", seen[:message]
    assert_equal "Writing to Bright Dental", seen[:context]
  end

  # --- the shape of the answer ---

  def test_truncates_a_message_too_long_to_carry
    seen = nil
    capturing = Object.new
    capturing.define_singleton_method(:evaluate) do |state:, decisions:, model: nil|
      seen = state
      Ask::DecisionResult::Batch.new(answers: {}, model: "static")
    end

    Ask::Decisions::Triage.new(capturing, lanes: LANES).read(message: "x" * 5000)

    assert_operator seen[:message].length, :<, 2100
    assert_includes seen[:message], "chars elided"
  end

  def test_a_verdict_with_no_lane_is_not_known
    silent = Object.new
    silent.define_singleton_method(:evaluate) do |state:, decisions:, model: nil|
      Ask::DecisionResult::Batch.new(answers: {}, model: "static")
    end

    verdict = Ask::Decisions::Triage.new(silent, lanes: LANES).read(message: "hello")

    refute verdict.known?
    refute verdict.certain?
    assert_equal "no verdict", verdict.to_s
  end

  def test_a_coin_flip_is_not_a_want_for_a_human
    answers = {
      "lane" => choice("lane", "knowledge", 0.9),
      "wants_human" => Ask::DecisionResult::NoulAnswer.new(id: "wants_human", noul: 0.5)
    }

    refute triage(answers: answers).read(message: "?").wants_human?
  end
end
