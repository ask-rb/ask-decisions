# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::ArgumentResolverTest < Minitest::Test
  SCHEMA_WITH_ENUM = {
    "type" => "object",
    "properties" => {
      "team" => { "type" => "string", "enum" => ["eng", "design", "growth"], "description" => "Team" },
      "priority" => { "type" => "string", "enum" => ["low", "medium", "high"], "description" => "Priority" },
      "title" => { "type" => "string", "description" => "Issue title" }
    },
    "required" => ["team", "title"]
  }.freeze

  SCHEMA_WITH_BOOL = {
    "type" => "object",
    "properties" => {
      "verbose" => { "type" => "boolean", "description" => "Verbose output" },
      "name" => { "type" => "string", "description" => "Name" }
    }
  }.freeze

  def test_resolves_enum_params
    provider = Ask::Decisions::Static.new(answers: {
      "team" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "team", choice: "eng",
        probabilities: { "eng" => 0.9, "design" => 0.05, "growth" => 0.05 },
        confidence: 0.9
      ),
      "priority" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "priority", choice: "high",
        probabilities: { "low" => 0.1, "medium" => 0.2, "high" => 0.7 },
        confidence: 0.7
      )
    })
    resolver = Ask::Decisions::ArgumentResolver.new(provider)
    result = resolver.resolve(
      tool_name: "linear.create_issue",
      params_schema: SCHEMA_WITH_ENUM,
      user_turn: "create a high-priority bug in the eng team"
    )

    assert_equal "eng", result.resolved["team"]
    assert_equal "high", result.resolved["priority"]
    assert_includes result.needs_generation, "title"
    assert result.needs_generation?
  end

  def test_resolves_boolean_params
    provider = Ask::Decisions::Static.new(answers: {
      "verbose" => Ask::DecisionResult::NoulAnswer.new(id: "verbose", noul: 0.8)
    })
    resolver = Ask::Decisions::ArgumentResolver.new(provider)
    result = resolver.resolve(
      tool_name: "bash",
      params_schema: SCHEMA_WITH_BOOL,
      user_turn: "run with verbose output"
    )

    assert_equal true, result.resolved["verbose"]
    assert_includes result.needs_generation, "name"
  end

  def test_all_free_text
    schema = {
      "type" => "object",
      "properties" => {
        "query" => { "type" => "string", "description" => "Search query" }
      }
    }
    resolver = Ask::Decisions::ArgumentResolver.new(Ask::Decisions::Static.new)
    result = resolver.resolve(
      tool_name: "web_search",
      params_schema: schema,
      user_turn: "search for ruby gems"
    )

    assert result.resolved.empty?
    assert_includes result.needs_generation, "query"
  end

  def test_empty_schema
    resolver = Ask::Decisions::ArgumentResolver.new(Ask::Decisions::Static.new)
    result = resolver.resolve(
      tool_name: "ls",
      params_schema: { "type" => "object", "properties" => {} },
      user_turn: "list files"
    )

    assert result.resolved.empty?
    assert result.needs_generation.empty?
  end

  def test_confidence
    provider = Ask::Decisions::Static.new(answers: {
      "team" => Ask::DecisionResult::ChoiceAnswer.new(
        id: "team", choice: "eng",
        probabilities: { "eng" => 0.9, "design" => 0.1 },
        confidence: 0.9
      )
    })
    resolver = Ask::Decisions::ArgumentResolver.new(provider)
    result = resolver.resolve(
      tool_name: "linear.create_issue",
      params_schema: SCHEMA_WITH_ENUM,
      user_turn: "create an issue"
    )

    assert result.confident?(0.5)
    refute result.confident?(0.95)
  end
end
