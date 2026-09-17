# frozen_string_literal: true

require "test_helper"

# Minimal stub for tool_call objects in tests.
ToolCallStub = Struct.new(:name, :arguments, keyword_init: true)
ResultStub = Struct.new(:output, keyword_init: true)

class Ask::Decisions::AgentAdapterTest < Minitest::Test
  def setup
    @provider = Ask::Decisions::Static.new
  end

  def test_creates_adapter_with_provider
    adapter = Ask::Decisions::AgentAdapter.new(:static)
    assert adapter.provider
    assert adapter.gate
    assert adapter.output_judge
    assert adapter.failure_classifier
    assert adapter.loop_detector
    assert adapter.confidence_policy
    assert adapter.quality_judge
    assert adapter.reflection_judge
    assert adapter.tool_repairer
  end

  def test_before_tool_hooks_return_array
    adapter = Ask::Decisions::AgentAdapter.new(:static)
    hooks = adapter.before_tool_hooks
    assert Array(hooks).any?
  end

  def test_after_tool_hooks_return_array
    adapter = Ask::Decisions::AgentAdapter.new(:static)
    hooks = adapter.after_tool_hooks
    assert Array(hooks).any?
  end

  def test_gate_hook_blocks_destructive
    # Use a provider that flags destructive actions
    provider = Ask::Decisions::Static.new(answers: {
      "destructive" => Ask::DecisionResult::NoulAnswer.new(id: "destructive", noul: 0.99),
      "exfiltration" => Ask::DecisionResult::NoulAnswer.new(id: "exfiltration", noul: 0.04),
      "beyond_scope" => Ask::DecisionResult::NoulAnswer.new(id: "beyond_scope", noul: 0.98),
      "impact" => Ask::DecisionResult::ScoreAnswer.new(
        id: "impact", score: 3.0,
        legend: { "0" => "No damage", "1" => "Minor", "2" => "Moderate", "3" => "Severe" },
        probabilities: { "0" => 0.0, "1" => 0.0, "2" => 0.0, "3" => 1.0 },
        confidence: 0.99
      )
    })
    adapter = Ask::Decisions::AgentAdapter.new(:static)
    # Override the gate with our flagged provider
    adapter.instance_variable_set(:@gate, Ask::Decisions::Gate.new(provider))

    hook = adapter.before_tool_hooks.first
    # Simulate a tool_call object
    tool_call = ToolCallStub.new(name: "bash", arguments: { command: "rm -rf src" })
    result = hook.call(tool_call, {})

    assert_equal :block, result[:action]
    assert result[:reason].include?("flagged")
  end

  def test_gate_hook_passes_safe_command
    adapter = Ask::Decisions::AgentAdapter.new(:static)
    hook = adapter.before_tool_hooks.first
    tool_call = ToolCallStub.new(name: "bash", arguments: { command: "git status" })
    result = hook.call(tool_call, {})

    assert_equal :proceed, result[:action]
  end

  def test_output_judge_hook_passes_clean_output
    adapter = Ask::Decisions::AgentAdapter.new(:static)
    hook = adapter.after_tool_hooks.first
    tool_call = ToolCallStub.new(name: "bash", arguments: {})
    result_obj = ResultStub.new(output: "On branch main\nnothing to commit")
    result = hook.call(tool_call, result_obj)

    assert_equal :proceed, result[:action]
  end

  def test_repair_tool_call
    adapter = Ask::Decisions::AgentAdapter.new(:static)
    tool_call = ToolCallStub.new(name: "bsh", arguments: { command: "ls" })
    tools = [{ name: "bash", description: "Run a shell command" }]

    result = adapter.repair_tool_call(tool_call, tools)
    assert result.repaired_tool
  end

  def test_classify_failure
    adapter = Ask::Decisions::AgentAdapter.new(:static)
    result = adapter.classify_failure(tool: "bash", output: "OK", attempt: 1)
    assert result.failure_class
  end

  def test_check_loop
    adapter = Ask::Decisions::AgentAdapter.new(:static)
    verdict = adapter.check_loop(recent_turns: [], turn_count: 1)
    assert verdict
  end

  def test_evaluate_quality
    adapter = Ask::Decisions::AgentAdapter.new(:static)
    verdict = adapter.evaluate_quality(request: "q", response: "a")
    assert verdict.scores.any?
  end

  def test_reflect
    adapter = Ask::Decisions::AgentAdapter.new(:static)
    verdict = adapter.reflect(request: "q", response: "a", attempt: 1)
    assert verdict.quality_score >= 0
  end

  def test_evaluate_confidence
    adapter = Ask::Decisions::AgentAdapter.new(:static)
    decision = adapter.evaluate_confidence(tool: "bash", confidence: 0.9)
    assert decision.act? || decision.review? || decision.escalate?
  end
end
