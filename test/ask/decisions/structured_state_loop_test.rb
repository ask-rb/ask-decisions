# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::StructuredStateLoopTest < Minitest::Test
  def test_completes_when_goal_met
    provider = Ask::Decisions::Static.new(answers: {
      "action_type" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "action_type", choice: "done",
        probabilities: { "done" => 1.0 }, confidence: 0.99
      ),
      "target" => Ask::DecisionResult::NoulAnswer.new(id: "target", noul: 0.95)
    })
    loop_runner = Ask::Decisions::StructuredStateLoop.new(provider)

    actions = []
    result = loop_runner.run(
      goal: "open Safari",
      state_fn: -> { { screen: "desktop" } },
      action_fn: ->(a) { actions << a },
      max_steps: 5
    )

    assert result.completed?
    assert_equal 1, result.steps
  end

  def test_stops_at_max_steps
    provider = Ask::Decisions::Static.new(answers: {
      "action_type" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "action_type", choice: "click",
        probabilities: { "click" => 1.0 }, confidence: 0.9
      ),
      "target" => Ask::DecisionResult::NoulAnswer.new(id: "target", noul: 0.1)
    })
    loop_runner = Ask::Decisions::StructuredStateLoop.new(provider)

    result = loop_runner.run(
      goal: "do something complex",
      state_fn: -> { { screen: "loading" } },
      action_fn: ->(_) {},
      max_steps: 3
    )

    refute result.completed?
    assert_equal 3, result.steps
  end

  def test_history_recorded
    call_count = 0
    provider = Ask::Decisions::Static.new(answers: {
      "action_type" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "action_type", choice: "type",
        probabilities: { "type" => 1.0 }, confidence: 0.9
      ),
      "target" => Ask::DecisionResult::NoulAnswer.new(id: "target", noul: 0.1)
    })
    loop_runner = Ask::Decisions::StructuredStateLoop.new(provider)

    result = loop_runner.run(
      goal: "type hello",
      state_fn: -> { { screen: "editor" } },
      action_fn: ->(_) { call_count += 1 },
      max_steps: 2
    )

    assert_equal 2, result.history.size
    assert_equal 2, call_count
  end

  def test_to_s
    result = Ask::Decisions::StructuredStateLoop::LoopResult.new(
      completed: true, steps: 5, history: []
    )
    assert result.to_s.include?("5")
  end
end
