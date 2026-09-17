# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::ReaderTest < Minitest::Test
  LANES = {
    "knowledge" => "Asks about the business",
    "booking" => "Wants to book"
  }.freeze

  # Records what it was asked, and answers whatever it is told to.
  class Recorder < Ask::DecisionProvider
    attr_reader :state, :decisions, :model

    def initialize(answers: {})
      super()
      @answers = answers
    end

    def evaluate(state:, decisions:, model: nil)
      @state = state
      @decisions = decisions
      @model = model
      Ask::DecisionResult::Batch.new(answers: @answers, model: model || "recorder")
    end
  end

  def reader(provider, **options)
    Ask::Decisions::Reader.new(
      provider, id: "lane", instructions: "Which of these?", options: LANES, **options
    )
  end

  # --- what gets asked ---

  def test_asks_the_options_as_one_choice
    provider = Recorder.new
    reader(provider).read(state: "hello")

    question = provider.decisions["lane"]

    assert_equal :choice, question.type
    assert_equal LANES, question.criteria
    assert_equal "Which of these?", question.instructions
  end

  def test_asks_everything_in_one_request
    urgent = Ask::Decision::Noul.new(instructions: "Is this urgent?")
    provider = Recorder.new
    reader(provider, also: {"urgent" => urgent}).read(state: "hello")

    assert_equal %w[lane urgent], provider.decisions.keys.sort
    assert_equal urgent, provider.decisions["urgent"]
  end

  def test_passes_the_state_and_model_through
    provider = Recorder.new
    reader(provider).read(state: {message: "hi"}, model: "jev-latest")

    assert_equal({message: "hi"}, provider.state)
    assert_equal "jev-latest", provider.model
  end

  # --- what comes back ---

  def test_reads_the_choice_by_its_id
    provider = Recorder.new(answers: {
      "lane" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "lane", choice: "booking", probabilities: {"booking" => 0.9}, confidence: 0.9
      )
    })
    reading = reader(provider)

    assert_equal "booking", reading.choice(reading.read(state: "hi")).choice
  end

  def test_a_choice_nobody_answered_is_nil
    reading = reader(Recorder.new)

    assert_nil reading.choice(reading.read(state: "hi"))
  end

  # --- the option descriptions ---

  def test_keeps_a_short_description_whole
    provider = Recorder.new
    reader(provider).read(state: "hi")

    assert_equal "Asks about the business", provider.decisions["lane"].criteria["knowledge"]
  end

  # A clipped option that does not say it was clipped reads as a whole one.
  def test_says_so_when_it_drops_part_of_a_description
    long = "x" * 500
    provider = Recorder.new
    Ask::Decisions::Reader.new(
      provider, id: "lane", instructions: "?", options: {"a" => long}, limit: 100
    ).read(state: "hi")

    criteria = provider.decisions["lane"].criteria["a"]

    assert_operator criteria.length, :<, 130
    assert_includes criteria, "chars elided"
  end

  # --- misuse ---

  def test_refuses_to_ask_one_id_twice
    assert_raises(ArgumentError) do
      reader(Recorder.new, also: {"lane" => Ask::Decision::Noul.new(instructions: "?")})
    end
  end
end
