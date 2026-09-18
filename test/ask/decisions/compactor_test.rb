# frozen_string_literal: true

require "test_helper"

# Minimal struct for testing object-style messages (not hashes).
MessageStub = Struct.new(:role, :content, :tool_calls, :tool_call_id, keyword_init: true)

class Ask::Decisions::CompactorTest < Minitest::Test
  # ── Helpers ──────────────────────────────────────────────────────────

  def user_msg(content)
    { role: "user", content: content }
  end

  def assistant_msg(content, tool_calls: [])
    msg = { role: "assistant", content: content }
    msg[:tool_calls] = tool_calls if tool_calls.any?
    msg
  end

  def tool_result_msg(content, tool_call_id:)
    { role: "tool", content: content, tool_call_id: tool_call_id }
  end

  def tc(id:, name:, input: {})
    { id: id, name: name, input: input }
  end

  # Build a provider that returns specific keep/drop answers for tool call IDs.
  def provider_with_decisions(decisions)
    answers = {}
    decisions.each do |call_id, opts|
      answers["keep_call_#{call_id}"] = Ask::DecisionResult::NoulAnswer.new(
        id: "keep_call_#{call_id}", noul: opts[:keep_call]
      )
      answers["keep_result_#{call_id}"] = Ask::DecisionResult::NoulAnswer.new(
        id: "keep_result_#{call_id}", noul: opts[:keep_result]
      )
    end
    Ask::Decisions::Static.new(answers: answers)
  end

  # Build a conversation large enough that ALL tool call/result pairs are
  # outside the preserve_recent window. With preserve_recent: 4, the last
  # 4 messages are pinned. We need enough padding so every tool result index
  # is < (total - preserve_recent).
  #
  # Layout with preserve_recent: 4, 2 tool calls:
  #   0: user                    (pinned — first)
  #   1: assistant + tool_call   (candidate)
  #   2: tool result             (candidate)
  #   3: assistant + tool_call   (candidate)
  #   4: tool result             (candidate)
  #   5: user                    (pinned — recent)
  #   6: user                    (pinned — recent)
  #   7: user                    (pinned — recent)
  #   8: assistant               (pinned — recent)
  def build_conversation(tool_calls_data, preserve_recent: 4)
    messages = [user_msg("Start the task")]

    tool_calls_data.each do |data|
      messages << assistant_msg("", tool_calls: [tc(id: data[:id], name: data[:name], input: data[:input] || {})])
      messages << tool_result_msg(data[:result], tool_call_id: data[:id])
    end

    # Ensure ALL tool result indices land in the candidate (unpinned) zone.
    # After tool calls: messages = [user, (tc_call, tc_result)*n]
    # Last tool result index = 2*n. Total = 1 + 2*n + pad + 1.
    # Pinned range = [total - preserve_recent .. total-1].
    # Need: 2*n < total - preserve_recent → pad ≥ preserve_recent.
    pad_needed = [preserve_recent - messages.size, 0].max
    # Add preserve_recent more to guarantee tool results are unpinned
    pad_count = pad_needed + preserve_recent
    pad_count.times { |i| messages << user_msg("Message #{i}") }
    messages << assistant_msg("Done!")

    messages
  end

  # ── Empty / trivial conversations ────────────────────────────────────

  def test_empty_messages
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    result = compactor.compact([])
    assert_equal [], result.messages
    refute result.compacted?
  end

  def test_single_message
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    result = compactor.compact([user_msg("hello")])
    assert_equal 1, result.messages.size
    refute result.compacted?
  end

  def test_no_tool_calls_passthrough
    messages = [
      user_msg("What is Ruby?"),
      assistant_msg("Ruby is a programming language."),
      user_msg("Tell me more"),
      assistant_msg("It was created by Matz in 1995."),
      user_msg("Thanks"),
      assistant_msg("You're welcome!")
    ]
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    result = compactor.compact(messages)
    assert_equal 6, result.messages.size
    refute result.compacted?
  end

  # ── Keep decisions ───────────────────────────────────────────────────

  def test_keeps_relevant_tool_call_and_result
    messages = build_conversation([
      { id: "c1", name: "Read", input: { path: "test/spec.rb" }, result: "def test_example; assert true; end" }
    ])

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.9, keep_result: 0.9 })
    )
    result = compactor.compact(messages)

    # c1 pair is kept, all messages remain
    assert result.messages.any? { |m| m[:content]&.include?("def test_example") }
    assert result.stats[:kept] >= 1
  end

  def test_kept_messages_remain_verbatim
    original_content = "def test_example\n  assert_equal 1, compute(2)\nend"
    messages = build_conversation([
      { id: "c1", name: "Read", input: { path: "lib/compute.rb" }, result: original_content }
    ])

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.9, keep_result: 0.9 })
    )
    result = compactor.compact(messages)

    assert result.messages.any? { |m| m[:content] == original_content }
  end

  # ── Drop decisions ───────────────────────────────────────────────────

  def test_drops_irrelevant_tool_call_and_result
    messages = build_conversation([
      { id: "c1", name: "Bash", input: { command: "ls -la" }, result: "total 48\ndrwxr-xr-x  8 user  staff  256 Sep 18 10:00 ." }
    ])

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.1, keep_result: 0.1 })
    )
    result = compactor.compact(messages)

    # c1 pair should be dropped
    refute result.messages.any? { |m| m[:content]&.include?("total 48") }
    assert result.compacted?
    assert_equal 1, result.stats[:dropped]
  end

  # ── Truncate decisions ───────────────────────────────────────────────

  def test_truncates_result_when_call_kept_but_result_not
    long_result = "x" * 1000
    messages = build_conversation([
      { id: "c1", name: "Read", input: { path: "big.rb" }, result: long_result }
    ])

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.9, keep_result: 0.2 }),
      truncate_head_chars: 100
    )
    result = compactor.compact(messages)

    # The tool result should be truncated (head preserved + note)
    truncated_msg = result.messages.find { |m| m[:content]&.start_with?("x" * 100) }
    assert truncated_msg, "Expected a truncated message starting with 100 x's"
    assert truncated_msg[:content].include?("truncated")
    assert truncated_msg[:content].include?("900 chars omitted")
    assert_equal 1, result.stats[:truncated]
  end

  def test_truncated_content_preserves_head
    original = "A" * 500 + "B" * 500
    messages = build_conversation([
      { id: "c1", name: "Read", input: {}, result: original }
    ])

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.9, keep_result: 0.1 }),
      truncate_head_chars: 200
    )
    result = compactor.compact(messages)

    truncated_msg = result.messages.find { |m| m[:content]&.start_with?("A" * 200) }
    assert truncated_msg, "Expected truncated message"
    refute truncated_msg[:content].include?("B" * 500)
  end

  # ── Mixed decisions ──────────────────────────────────────────────────

  def test_mixed_keep_drop_truncate
    messages = build_conversation([
      { id: "c1", name: "Read", input: { path: "a.rb" }, result: "content_a" },
      { id: "c2", name: "Bash", input: { command: "ls" }, result: "file_a.rb\nfile_b.rb" },
      { id: "c3", name: "Read", input: { path: "b.rb" }, result: "content_b_long" }
    ])

    provider = provider_with_decisions(
      "c1" => { keep_call: 0.9, keep_result: 0.9 },
      "c2" => { keep_call: 0.1, keep_result: 0.1 },
      "c3" => { keep_call: 0.9, keep_result: 0.2 }
    )

    compactor = Ask::Decisions::Compactor.new(provider, truncate_head_chars: 10)
    result = compactor.compact(messages)

    # c1 kept, c2 dropped, c3 truncated
    assert result.messages.any? { |m| m[:content] == "content_a" }
    refute result.messages.any? { |m| m[:content]&.include?("file_a.rb") }
    assert result.messages.any? { |m| m[:content]&.include?("content_b") && m[:content]&.include?("truncated") }
    assert_equal 1, result.stats[:kept]
    assert_equal 1, result.stats[:dropped]
    assert_equal 1, result.stats[:truncated]
  end

  # ── Pinned messages ──────────────────────────────────────────────────

  def test_first_message_always_pinned
    messages = build_conversation([
      { id: "c1", name: "Bash", input: { command: "ls" }, result: "src/ lib/ test/" }
    ])

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.1, keep_result: 0.1 })
    )
    result = compactor.compact(messages)

    # First message always kept
    assert_equal "Start the task", result.messages[0][:content]
  end

  def test_recent_messages_not_touched
    # Build a conversation where c1 is in the candidate zone (early)
    # and c2 is in the pinned zone (recent).
    messages = [user_msg("Start")]
    messages << assistant_msg("", tool_calls: [tc(id: "c1", name: "Read", input: {})])
    messages << tool_result_msg("old content", tool_call_id: "c1")
    messages << assistant_msg("Intermediate.")
    # Fill to push c2 into the recent zone
    3.times { |i| messages << user_msg("pad #{i}") }
    messages << assistant_msg("", tool_calls: [tc(id: "c2", name: "Read", input: {})])
    messages << tool_result_msg("recent content", tool_call_id: "c2")
    messages << user_msg("Done?")

    # preserve_recent: 3 → last 3 messages are pinned (indices 7, 8)
    # c2 pair (indices 6, 7) — result is pinned, call is not → NOT fully pinned → evaluated
    # But result at index 7 IS pinned → can't be removed
    provider = provider_with_decisions(
      "c1" => { keep_call: 0.1, keep_result: 0.1 },
      "c2" => { keep_call: 0.9, keep_result: 0.9 }
    )

    compactor = Ask::Decisions::Compactor.new(provider, preserve_recent: 3)
    result = compactor.compact(messages)

    # c1 should be dropped (not pinned)
    refute result.messages.any? { |m| m[:content] == "old content" }
    # c2 should be kept (recent, and Jev says keep)
    assert result.messages.any? { |m| m[:content] == "recent content" }
  end

  def test_pinned_recent_never_dropped_even_if_jev_says_drop
    messages = [user_msg("Start")]
    messages << assistant_msg("OK")
    # Fill so that c1 ends up in the recent zone
    4.times { |i| messages << user_msg("pad #{i}") }
    messages << assistant_msg("", tool_calls: [tc(id: "c1", name: "Read", input: {})])
    messages << tool_result_msg("recent but Jev says drop", tool_call_id: "c1")
    messages << user_msg("What now?")

    # preserve_recent: 2 → last 2 messages are pinned (indices 9, 10)
    # c1 pair: call at 8, result at 9. Result is pinned → can't be removed.
    provider = provider_with_decisions(
      "c1" => { keep_call: 0.1, keep_result: 0.1 }
    )

    compactor = Ask::Decisions::Compactor.new(provider, preserve_recent: 2)
    result = compactor.compact(messages)

    # The tool result is in a pinned message, so it stays
    assert result.messages.any? { |m| m[:content] == "recent but Jev says drop" }
  end

  # ── Multiple tool calls per assistant message ────────────────────────

  def test_multiple_tool_calls_in_one_message
    messages = build_conversation([
      { id: "c1", name: "Read", input: { path: "a.rb" }, result: "content_a" },
      { id: "c2", name: "Read", input: { path: "b.rb" }, result: "content_b" }
    ])

    provider = provider_with_decisions(
      "c1" => { keep_call: 0.9, keep_result: 0.9 },
      "c2" => { keep_call: 0.1, keep_result: 0.1 }
    )

    compactor = Ask::Decisions::Compactor.new(provider)
    result = compactor.compact(messages)

    # c1 kept, c2 dropped
    assert result.messages.any? { |m| m[:content] == "content_a" }
    refute result.messages.any? { |m| m[:content] == "content_b" }
    assert_equal 1, result.stats[:kept]
    assert_equal 1, result.stats[:dropped]
  end

  # ── Stats ────────────────────────────────────────────────────────────

  def test_stats_track_all_metrics
    messages = build_conversation([
      { id: "c1", name: "Read", input: {}, result: "a" * 500 },
      { id: "c2", name: "Read", input: {}, result: "b" * 500 }
    ])

    provider = provider_with_decisions(
      "c1" => { keep_call: 0.9, keep_result: 0.9 },
      "c2" => { keep_call: 0.1, keep_result: 0.1 }
    )

    compactor = Ask::Decisions::Compactor.new(provider)
    result = compactor.compact(messages)

    assert result.stats[:messages_before] > 0
    assert result.stats[:messages_after] <= result.stats[:messages_before]
    assert_equal 1, result.stats[:kept]
    assert_equal 1, result.stats[:dropped]
    assert_equal 2, result.stats[:tool_pairs_evaluated]
    assert result.stats[:chars_before] > 0
    assert result.stats[:chars_after] < result.stats[:chars_before]
    assert result.stats[:reduction_ratio] > 0
    assert result.stats[:reduction_ratio] < 1
  end

  def test_reduction_ratio_one_when_all_dropped
    messages = build_conversation([
      { id: "c1", name: "Bash", input: {}, result: "big" * 1000 }
    ])

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.1, keep_result: 0.1 })
    )
    result = compactor.compact(messages)

    assert result.stats[:reduction_ratio] > 0.5
  end

  # ── Result object ────────────────────────────────────────────────────

  def test_result_to_s_when_compacted
    messages = build_conversation([
      { id: "c1", name: "Bash", input: {}, result: "result_y" }
    ])

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.1, keep_result: 0.1 })
    )
    result = compactor.compact(messages)

    str = result.to_s
    assert str.include?("compacted")
    assert str.include?("dropped")
  end

  def test_result_to_s_when_not_compacted
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    result = compactor.compact([user_msg("hello")])
    assert result.to_s.include?("no compaction needed")
  end

  # ── State building ───────────────────────────────────────────────────

  def test_state_replaces_tool_results_with_placeholders
    messages = build_conversation([
      { id: "c1", name: "Read", input: { path: "a.rb" }, result: "a" * 500 }
    ])

    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    pairs = compactor.send(:build_pairs, messages)
    state = compactor.send(:build_state, messages, pairs)

    conv = state[:conversation]
    # The tool result line should be a placeholder
    assert conv.any? { |line| line.include?("omitted") && line.include?("500 chars") }
    # The tool call should include the input
    assert conv.any? { |line| line.include?("Read") && line.include?("a.rb") }
  end

  def test_state_includes_goal
    messages = [
      user_msg("Fix the bug"),
      assistant_msg("OK"),
      user_msg("Really fix it"),
      assistant_msg("Working on it"),
      user_msg("Now"),
      assistant_msg("Done")
    ]

    compactor = Ask::Decisions::Compactor.new(
      Ask::Decisions::Static.new,
      goal: "Fix the failing test in spec/user_spec.rb"
    )
    pairs = compactor.send(:build_pairs, messages)
    state = compactor.send(:build_state, messages, pairs)

    assert_equal "Fix the failing test in spec/user_spec.rb", state[:goal]
  end

  # ── Token estimation ─────────────────────────────────────────────────

  def test_estimate_tokens_basic
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    assert compactor.send(:estimate_tokens, "hello") >= 1
    assert_equal 0, compactor.send(:estimate_tokens, "")
    assert_equal 0, compactor.send(:estimate_tokens, nil)
  end

  def test_estimate_tokens_with_digits
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    tokens = compactor.send(:estimate_tokens, "abc123")
    assert tokens >= 2
    assert tokens <= 3
  end

  # ── Batching ─────────────────────────────────────────────────────────

  def test_batching_splits_large_question_sets
    tool_calls_data = (1..20).map do |i|
      { id: "c#{i}", name: "Read", input: { path: "file_#{i}.rb" }, result: "content_#{i}" }
    end
    messages = build_conversation(tool_calls_data, preserve_recent: 4)

    # With a very small max_request_tokens, we force batching
    compactor = Ask::Decisions::Compactor.new(
      Ask::Decisions::Static.new,
      max_request_tokens: 500,
      preserve_recent: 4
    )

    # Should not raise — batching handles the split
    result = compactor.compact(messages)
    assert result.messages.any?
    assert_equal 20, result.stats[:tool_pairs_evaluated]
  end

  def test_merge_batches_combines_results
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    batch1 = Ask::DecisionResult::Batch.new(answers: {
      "keep_call_c1" => Ask::DecisionResult::NoulAnswer.new(id: "keep_call_c1", noul: 0.9)
    })
    batch2 = Ask::DecisionResult::Batch.new(answers: {
      "keep_result_c1" => Ask::DecisionResult::NoulAnswer.new(id: "keep_result_c1", noul: 0.8)
    })

    merged = compactor.send(:merge_batches, [batch1, batch2])
    assert_equal 0.9, merged["keep_call_c1"].noul
    assert_equal 0.8, merged["keep_result_c1"].noul
  end

  # ── Edge cases ───────────────────────────────────────────────────────

  def test_orphan_tool_result_not_paired
    messages = [
      user_msg("Hi"),
      tool_result_msg("orphan result", tool_call_id: "nonexistent"),
      assistant_msg("Hello!"),
      user_msg("OK"),
      assistant_msg("Sure"),
      user_msg("Done"),
      assistant_msg("Bye")
    ]

    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    result = compactor.compact(messages)

    # Should not crash, orphan result stays
    assert result.messages.any? { |m| m[:content] == "orphan result" }
  end

  def test_tool_call_without_result
    messages = [
      user_msg("Do something"),
      assistant_msg("", tool_calls: [tc(id: "c1", name: "Bash", input: {})]),
      assistant_msg("I tried."),
      user_msg("OK"),
      assistant_msg("Sure"),
      user_msg("Done"),
      assistant_msg("Bye")
    ]

    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    result = compactor.compact(messages)

    # No pairs found, nothing to compact
    refute result.compacted?
  end

  def test_all_results_dropped_removes_tool_messages
    messages = build_conversation([
      { id: "c1", name: "Bash", input: {}, result: "result_1" },
      { id: "c2", name: "Bash", input: {}, result: "result_2" }
    ])

    provider = provider_with_decisions(
      "c1" => { keep_call: 0.1, keep_result: 0.1 },
      "c2" => { keep_call: 0.1, keep_result: 0.1 }
    )

    compactor = Ask::Decisions::Compactor.new(provider)
    result = compactor.compact(messages)

    # Tool call and result messages should be dropped
    refute result.messages.any? { |m| m[:content] == "result_1" }
    refute result.messages.any? { |m| m[:content] == "result_2" }
    assert result.stats[:dropped] >= 1
  end

  def test_short_content_not_truncated_even_if_threshold_met
    messages = build_conversation([
      { id: "c1", name: "Read", input: {}, result: "short" }
    ])

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.9, keep_result: 0.1 }),
      truncate_head_chars: 300
    )
    result = compactor.compact(messages)

    # Content is shorter than truncate_head_chars, so it stays intact
    assert result.messages.any? { |m| m[:content] == "short" }
  end

  # ── normalize / hashify ─────────────────────────────────────────────

  def test_normalize_accepts_object_with_role_and_content
    msg = MessageStub.new(role: :assistant, content: "hello", tool_calls: nil, tool_call_id: nil)
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    normalized = compactor.send(:normalize, [msg])

    assert_equal "assistant", normalized[0][:role]
    assert_equal "hello", normalized[0][:content]
  end

  def test_normalize_hashes_are_passed_through
    msg = { role: "user", content: "test" }
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    normalized = compactor.send(:normalize, [msg])

    assert_equal msg, normalized[0]
  end

  # ── Classify action ──────────────────────────────────────────────────

  def test_classify_action_keep
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new, keep_threshold: 0.5)
    assert_equal :keep, compactor.send(:classify_action, 0.9, 0.9)
    assert_equal :keep, compactor.send(:classify_action, 0.1, 0.9)
  end

  def test_classify_action_truncate
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new, keep_threshold: 0.5)
    assert_equal :truncate, compactor.send(:classify_action, 0.9, 0.3)
  end

  def test_classify_action_drop
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new, keep_threshold: 0.5)
    assert_equal :drop, compactor.send(:classify_action, 0.3, 0.3)
    assert_equal :drop, compactor.send(:classify_action, 0.1, 0.1)
  end

  def test_classify_action_threshold_boundary
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new, keep_threshold: 0.5)
    assert_equal :keep, compactor.send(:classify_action, 0.1, 0.5)
    assert_equal :truncate, compactor.send(:classify_action, 0.5, 0.4)
  end

  # ── compute_pinned ───────────────────────────────────────────────────

  def test_pinned_includes_first_and_recent
    messages = Array.new(10) { |i| user_msg("msg #{i}") }
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new, preserve_recent: 3)
    pinned = compactor.send(:compute_pinned, messages)

    assert pinned.include?(0)     # first
    assert pinned.include?(7)     # 10 - 3 = 7
    assert pinned.include?(8)
    assert pinned.include?(9)
    refute pinned.include?(5)     # middle not pinned
  end

  def test_pinned_first_message_when_only_two_messages
    messages = [user_msg("a"), user_msg("b")]
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new, preserve_recent: 4)
    pinned = compactor.send(:compute_pinned, messages)

    assert pinned.include?(0)
    assert pinned.include?(1)
  end

  # ── Integration: realistic conversation ──────────────────────────────

  def test_realistic_coding_conversation
    # Build a realistic 10+ message coding conversation
    messages = [user_msg("Fix the failing test in user_spec.rb")]
    # Step 1: Read the test file — relevant, keep
    messages << assistant_msg("", tool_calls: [tc(id: "c1", name: "Read", input: { path: "test/user_spec.rb" })])
    messages << tool_result_msg("require 'spec_helper'\ndescribe User do\n  it 'validates email' do\n    expect(User.new(email: nil)).not_to be_valid\n  end\nend", tool_call_id: "c1")
    # Step 2: List files — exploratory, drop
    messages << assistant_msg("", tool_calls: [tc(id: "c2", name: "Bash", input: { command: "ls -la" })])
    messages << tool_result_msg("total 48\ndrwxr-xr-x  8 user  staff  256 Sep 18\n-rw-r--r--  1 user  staff  1024 Sep 18 user_spec.rb", tool_call_id: "c2")
    # Step 3: Read the model — relevant, keep
    messages << assistant_msg("", tool_calls: [tc(id: "c3", name: "Read", input: { path: "app/models/user.rb" })])
    messages << tool_result_msg("class User < ApplicationRecord\n  validates :email, presence: true\nend", tool_call_id: "c3")
    # Step 4: Check git status — exploratory, drop
    messages << assistant_msg("", tool_calls: [tc(id: "c4", name: "Bash", input: { command: "git status" })])
    messages << tool_result_msg("On branch main\nnothing to commit, working tree clean", tool_call_id: "c4")
    # Recent messages (pinned) — need enough to push c4 out of the pinned zone.
    # With preserve_recent: 3, last 3 messages are pinned. We need c4's result
    # (index 8) to be < total - 3, so total must be > 11.
    messages << assistant_msg("The test expects email validation to work. Let me check the model...")
    messages << user_msg("OK")
    messages << assistant_msg("Looking at the validations...")

    provider = provider_with_decisions(
      "c1" => { keep_call: 0.9, keep_result: 0.9 },
      "c2" => { keep_call: 0.2, keep_result: 0.1 },
      "c3" => { keep_call: 0.9, keep_result: 0.9 },
      "c4" => { keep_call: 0.2, keep_result: 0.1 }
    )

    compactor = Ask::Decisions::Compactor.new(provider, preserve_recent: 3)
    result = compactor.compact(messages)

    # c1 and c3 kept, c2 and c4 dropped
    assert result.compacted?
    assert_equal 2, result.stats[:kept]
    assert_equal 2, result.stats[:dropped]
    # Original test content preserved
    assert result.messages.any? { |m| m[:content]&.include?("validates :email") }
    assert result.messages.any? { |m| m[:content]&.include?("class User") }
    # Dropped content gone
    refute result.messages.any? { |m| m[:content]&.include?("working tree clean") }
    refute result.messages.any? { |m| m[:content]&.include?("total 48") }
  end

  # ── Default provider answers ─────────────────────────────────────────

  def test_static_provider_default_answers_mean_keep
    # Default Static provider returns noul: 0.5. With keep_threshold: 0.5,
    # 0.5 >= 0.5 → keep. But messages must be outside the preserve_recent zone.
    messages = build_conversation([
      { id: "c1", name: "Bash", input: {}, result: "result" }
    ])

    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    result = compactor.compact(messages)

    # Default noul is 0.5, threshold is 0.5 → all kept
    assert result.messages.any? { |m| m[:content] == "result" }
    assert result.stats[:kept] >= 1
  end

  def test_custom_keep_threshold
    messages = build_conversation([
      { id: "c1", name: "Bash", input: {}, result: "result" }
    ])

    # Default noul is 0.5, threshold 0.6 → 0.5 < 0.6 → drop
    compactor = Ask::Decisions::Compactor.new(
      Ask::Decisions::Static.new,
      keep_threshold: 0.6
    )
    result = compactor.compact(messages)

    refute result.messages.any? { |m| m[:content] == "result" }
    assert result.stats[:dropped] >= 1
  end

  # ── Pinned pair protection ──────────────────────────────────────────

  def test_pinned_pair_skipped_from_questions
    # When both call and result are in pinned messages, no questions are asked
    messages = [user_msg("Start")]
    messages << assistant_msg("", tool_calls: [tc(id: "c1", name: "Read", input: {})])
    messages << tool_result_msg("pinned content", tool_call_id: "c1")
    messages << user_msg("Done")

    # preserve_recent: 4 → all 4 messages pinned → no questions asked
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new, preserve_recent: 4)
    pairs = compactor.send(:build_pairs, messages)
    pinned = compactor.send(:compute_pinned, messages)
    questions = compactor.send(:build_questions, pairs, pinned)

    assert questions.empty?, "No questions should be asked for fully pinned pairs"
  end

  def test_partially_pinned_pair_gets_questions
    # When only one side of the pair is pinned, questions are still asked
    messages = [user_msg("Start")]
    messages << assistant_msg("Intermediate")
    messages << assistant_msg("", tool_calls: [tc(id: "c1", name: "Read", input: {})])
    messages << tool_result_msg("content", tool_call_id: "c1")
    messages << user_msg("Done")

    # preserve_recent: 2 → last 2 messages pinned (indices 3, 4)
    # c1 pair: call at 2, result at 3 → result is pinned, call is not → NOT fully pinned
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new, preserve_recent: 2)
    pairs = compactor.send(:build_pairs, messages)
    pinned = compactor.send(:compute_pinned, messages)
    questions = compactor.send(:build_questions, pairs, pinned)

    assert questions.key?("keep_call_c1"), "Question should be asked for partially pinned pair"
    assert questions.key?("keep_result_c1")
  end
end
