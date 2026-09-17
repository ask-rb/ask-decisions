# frozen_string_literal: true

require "test_helper"

class Ask::DecisionResult::ChoiceAnswerTest < Minitest::Test
  def setup
    @answer = Ask::DecisionResult::ChoiceAnswer.new(
      id: "route",
      choice: "technical",
      probabilities: { "billing" => 0.1, "technical" => 0.8, "sales" => 0.1 },
      confidence: 0.82
    )
  end

  def test_choice
    assert_equal "technical", @answer.choice
  end

  def test_ranked
    ranked = @answer.ranked
    assert_equal "technical", ranked.first[0]
    assert_in_delta 0.8, ranked.first[1], 0.001
  end

  def test_best
    assert_equal ["technical", 0.8], @answer.best
  end

  def test_confident_above_threshold
    assert @answer.confident?(0.7)
  end

  def test_not_confident_above_threshold
    refute @answer.confident?(0.9)
  end

  def test_confident_with_nil
    answer = Ask::DecisionResult::ChoiceAnswer.new(
      id: "q", choice: "a", probabilities: { "a" => 1.0 }, confidence: nil
    )
    refute answer.confident?(0.7)
  end

  def test_type
    assert_equal :choice, @answer.type
  end
end

class Ask::DecisionResult::ScoreAnswerTest < Minitest::Test
  def setup
    @answer = Ask::DecisionResult::ScoreAnswer.new(
      id: "frustration",
      score: 1.6,
      legend: { "0" => "Calm", "1" => "Frustrated", "2" => "Very angry" },
      probabilities: { "0" => 0.05, "1" => 0.3, "2" => 0.65 },
      confidence: 0.78
    )
  end

  def test_score
    assert_in_delta 1.6, @answer.score, 0.001
  end

  def test_expected
    assert_equal @answer.score, @answer.expected
  end

  def test_confident
    assert @answer.confident?(0.5)
  end

  def test_ranked
    ranked = @answer.ranked
    assert_equal "2", ranked.first[0]
  end
end

class Ask::DecisionResult::NoulAnswerTest < Minitest::Test
  def test_yes
    answer = Ask::DecisionResult::NoulAnswer.new(id: "q", noul: 0.92)
    assert answer.yes?
    refute answer.no?
    assert_in_delta 0.42, answer.strength, 0.001
  end

  def test_no
    answer = Ask::DecisionResult::NoulAnswer.new(id: "q", noul: 0.15)
    assert answer.no?
    refute answer.yes?
    assert_in_delta 0.35, answer.strength, 0.001
  end

  def test_uncertain
    answer = Ask::DecisionResult::NoulAnswer.new(id: "q", noul: 0.5)
    assert_in_delta 0.0, answer.strength, 0.001
    refute answer.confident?(0.3)
  end
end

class Ask::DecisionResult::BatchTest < Minitest::Test
  def setup
    @batch = Ask::DecisionResult::Batch.new(
      answers: {
        "route" => Ask::DecisionResult::ChoiceAnswer.new(
          id: "route", choice: "a", probabilities: { "a" => 0.9 }, confidence: 0.9
        ),
        "urgent" => Ask::DecisionResult::NoulAnswer.new(id: "urgent", noul: 0.8)
      },
      model: "jev-latest",
      usage: { "input_tokens" => 100, "output_tokens" => 10 }
    )
  end

  def test_access_by_id
    assert_equal "a", @batch["route"].choice
  end

  def test_enumerable
    types = @batch.map(&:type)
    assert_includes types, :choice
    assert_includes types, :noul
  end

  def test_min_confidence
    # noul has no confidence, so only choice counts
    assert_in_delta 0.9, @batch.min_confidence, 0.001
  end

  def test_all_confident
    assert @batch.all_confident?(0.5)
    refute @batch.all_confident?(0.95)
  end

  def test_model
    assert_equal "jev-latest", @batch.model
  end
end
