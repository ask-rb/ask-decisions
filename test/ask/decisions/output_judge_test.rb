# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::OutputJudgeTest < Minitest::Test
  def setup
    @provider = Ask::Decisions::Static.new
    @judge = Ask::Decisions::OutputJudge.new(@provider)
  end

  def test_clean_output
    result = @judge.judge(
      tool: "bash",
      output: "On branch main\nnothing to commit",
      args: { command: "git status" }
    )
    refute result.leak?
    assert_equal "no_failure", result.failure_class
    refute result.failure?
    assert_equal "clean", result.to_s
  end

  def test_secret_detected
    provider = Ask::Decisions::Static.new(answers: {
      "leaks_secret" => Ask::DecisionResult::NoulAnswer.new(id: "leaks_secret", noul: 0.95),
      "failure_class" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "failure_class", choice: "no_failure",
        probabilities: { "no_failure" => 1.0 }, confidence: 0.9
      )
    })
    judge = Ask::Decisions::OutputJudge.new(provider)
    result = judge.judge(tool: "bash", output: "AWS_SECRET_KEY=AKIA1234567890", args: {})

    assert result.leak?
    assert result.to_s.include?("LEAK")
  end

  def test_failure_classification
    provider = Ask::Decisions::Static.new(answers: {
      "leaks_secret" => Ask::DecisionResult::NoulAnswer.new(id: "leaks_secret", noul: 0.01),
      "failure_class" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "failure_class", choice: "transient",
        probabilities: { "transient" => 1.0 }, confidence: 0.95
      )
    })
    judge = Ask::Decisions::OutputJudge.new(provider)
    result = judge.judge(tool: "bash", output: "npm ERR! code ECONNRESET", args: {})

    assert result.failure?
    assert_equal "transient", result.failure_class
    assert_equal "Retry unchanged.", result.advice
  end

  def test_code_bug_classification
    provider = Ask::Decisions::Static.new(answers: {
      "leaks_secret" => Ask::DecisionResult::NoulAnswer.new(id: "leaks_secret", noul: 0.01),
      "failure_class" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "failure_class", choice: "code_bug",
        probabilities: { "code_bug" => 1.0 }, confidence: 1.0
      )
    })
    judge = Ask::Decisions::OutputJudge.new(provider)
    result = judge.judge(tool: "bash", output: "error TS2322: Type 'string' is not assignable", args: {})

    assert result.failure?
    assert_equal "code_bug", result.failure_class
    assert result.advice.include?("must change")
  end

  def test_tool_not_judged
    result = @judge.judge(tool: "read", output: "contents", args: {})
    refute result.leak?
    assert_equal "no_failure", result.failure_class
  end

  def test_output_truncation
    long_output = "x" * 5000
    judge = Ask::Decisions::OutputJudge.new(@provider, output_limit: 1000)
    # Should not raise
    result = judge.judge(tool: "bash", output: long_output, args: {})
    assert result
  end

  def test_json_encoded_tool_arguments_are_parsed_before_judging
    observed_state = nil
    provider = Object.new
    provider.define_singleton_method(:evaluate) do |state:, decisions:|
      observed_state = state
      Ask::DecisionResult::Batch.new(answers: {})
    end
    judge = Ask::Decisions::OutputJudge.new(provider)

    judge.judge(tool: "bash", output: "done", args: '{"command":"git status --short"}')

    assert_equal({"command" => "git status --short"}, observed_state[:tool_arguments])
  end

  def test_invalid_json_arguments_are_kept_as_opaque_data
    observed_state = nil
    provider = Object.new
    provider.define_singleton_method(:evaluate) do |state:, decisions:|
      observed_state = state
      Ask::DecisionResult::Batch.new(answers: {})
    end
    judge = Ask::Decisions::OutputJudge.new(provider)

    judge.judge(tool: "bash", output: "done", args: "not-json")

    assert_equal({"_raw_arguments" => "not-json"}, observed_state[:tool_arguments])
  end

  def test_all_advice_classes_covered
    Ask::Decisions::OutputJudge::ADVICE.each_key do |klass|
      assert Ask::Decisions::OutputJudge::ADVICE.key?(klass),
        "Missing advice for failure class: #{klass}"
    end
    assert_equal 6, Ask::Decisions::OutputJudge::ADVICE.size
  end
end

# The advice belongs to the host too: what a failure means for this business is
# not what it means for a coding agent.
class Ask::Decisions::OutputJudgeQuestionsTest < Minitest::Test
  QUESTIONS = {
    leaks_secret: Ask::Decision::Noul.new(
      instructions: "Does this output contain another customer's private information?"
    ),
    failure_class: Ask::Decision::Choice.new(
      instructions: "What happened?",
      criteria: {"no_failure" => "It worked", "no_such_thing" => "The business has nothing like that"}
    )
  }.freeze

  ADVICE = {"no_such_thing" => "Say plainly that the business does not offer that."}.freeze

  def judge(outcome, confidence: 0.9, leak: 0.0)
    provider = Ask::Decisions::Static.new(
      answers: {
        "leaks_secret" => Ask::DecisionResult::NoulAnswer.new(id: "leaks_secret", noul: leak),
        "failure_class" => Ask::DecisionResult::ChoiceAnswer.new(
          id: "failure_class", choice: outcome, confidence: confidence,
          probabilities: {"done" => confidence, "no_such_thing" => (1.0 - confidence).round(2)}
        )
      }
    )

    Ask::Decisions::OutputJudge.new(
      provider, questions: QUESTIONS, advice: ADVICE, tools: ["book_appointment"]
    ).judge(tool: "book_appointment", output: "no such treatment")
  end

  def test_the_hosts_class_and_its_advice_come_back
    result = judge("no_such_thing")

    assert result.failure?
    assert_equal "no_such_thing", result.failure_class
    assert_equal ADVICE["no_such_thing"], result.advice
  end

  def test_a_class_the_host_gave_no_line_for_gets_no_advice
    assert_nil judge("no_failure").advice
    refute judge("no_failure").failure?, "the host said what success is"
  end

  # Questions the result cannot read would judge nothing, silently.
  def test_questions_the_judge_cannot_read_are_refused
    error = assert_raises(ArgumentError) do
      Ask::Decisions::OutputJudge.new(
        Ask::Decisions::Static.new(answers: {}),
        questions: {leaked: QUESTIONS[:leaks_secret]}
      )
    end

    assert_includes error.message, ":failure_class"
  end

  # Without a class that means "nothing went wrong", every successful call
  # would read as a failure.
  def test_an_outcome_question_with_no_success_class_is_refused
    error = assert_raises(ArgumentError) do
      Ask::Decisions::OutputJudge.new(
        Ask::Decisions::Static.new(answers: {}),
        questions: QUESTIONS.merge(
          failure_class: Ask::Decision::Choice.new(
            instructions: "What happened?", criteria: {"broken" => "It broke"}
          )
        )
      )
    end

    assert_includes error.message, "no_failure"
  end

  def test_the_hosts_leak_question_is_what_blocks
    assert judge("done", leak: 0.99).leak?
    refute judge("done", leak: 0.10).leak?
  end
end
