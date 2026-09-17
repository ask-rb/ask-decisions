# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::BatcherTest < Minitest::Test
  def setup
    @provider = Ask::Decisions::Static.new
  end

  def test_single_question
    batcher = Ask::Decisions::Batcher.new(@provider, state: "test")
    batcher.ask("q", Ask::Decision::Noul.new(instructions: "Is it urgent?"))
    result = batcher.execute

    assert result["q"]
    assert result["q"].noul
  end

  def test_multiple_questions
    batcher = Ask::Decisions::Batcher.new(@provider, state: "test")
    batcher.ask("q1", Ask::Decision::Noul.new(instructions: "A?"))
    batcher.ask("q2", Ask::Decision::Choice.new(
      instructions: "Which?", criteria: { a: "A", b: "B" }
    ))
    result = batcher.execute

    assert result["q1"].noul
    assert result["q2"].choice
  end

  def test_empty_batch
    batcher = Ask::Decisions::Batcher.new(@provider, state: "test")
    result = batcher.execute

    assert_equal({}, result.answers)
  end

  def test_block_syntax
    result = Ask::Decisions.batch(state: "test", provider: :static) do |b|
      b.ask("q", Ask::Decision::Noul.new(instructions: "A?"))
    end

    assert result["q"].noul
  end
end
