# frozen_string_literal: true

require "test_helper"

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

  def tool_call(id:, name:, input: {})
    { id: id, name: name, input: input }
  end

  # Build a provider that returns specific keep/drop answers for tool call IDs.
  def provider_with_decisions(decisions)
    answers = {}
    decisions.each do |call_id, keep_call:, keep_result:|
      answers["keep_call_#{call_id}"] = Ask::DecisionResult::NoulAnswer.new(
        id: "keep_call_#{call_id}", noul: keep_call
      )
      answers["keep_result_#{call_id}"] = Ask::DecisionResult::NoulAnswer.new(
        id: "keep_result_#{call_id}", noul: keep_result
      )
    end
    Ask::Decisions::Static.new(answers: answers)
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
      assistant_msg("It was created by Matz in 1995.")
    ]
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    result = compactor.compact(messages)
    assert_equal 4, result.messages.size
    assert_equal messages, result.messages
    refute result.compacted?
  end

  # ── Keep decisions ───────────────────────────────────────────────────

  def test_keeps_relevant_tool_call_and_result
    messages = [
      user_msg("Fix the test"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Read", input: { path: "test/spec.rb" })]),
      tool_result_msg("def test_example; assert true; end", tool_call_id: "c1"),
      assistant_msg("The test looks fine.")
    ]

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.9, keep_result: 0.9 })
    )
    result = compactor.compact(messages)

    assert_equal 4, result.messages.size
    assert_equal messages[1], result.messages[1]
    assert_equal messages[2], result.messages[2]
    assert result.compacted? # decisions were made, even if nothing was dropped
    assert_equal 1, result.stats[:kept]
  end

  def test_kept_messages_remain_verbatim
    original_content = "def test_example\n  assert_equal 1, compute(2)\nend"
    messages = [
      user_msg("Check the code"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Read", input: { path: "lib/compute.rb" })]),
      tool_result_msg(original_content, tool_call_id: "c1"),
      assistant_msg("Looks correct.")
    ]

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.9, keep_result: 0.9 })
    )
    result = compactor.compact(messages)

    assert_equal original_content, result.messages[2][:content]
  end

  # ── Drop decisions ───────────────────────────────────────────────────

  def test_drops_irrelevant_tool_call_and_result
    messages = [
      user_msg("What's 2+2?"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Bash", input: { command: "ls -la" })]),
      tool_result_msg("total 48\ndrwxr-xr-x  8 user  staff  256 Sep 18 10:00 .", tool_call_id: "c1"),
      assistant_msg("The answer is 4.")
    ]

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.1, keep_result: 0.1 })
    )
    result = compactor.compact(messages)

    # Both the tool call assistant message and the tool result should be removed
    assert_equal 2, result.messages.size
    assert_equal "user", result.messages[0][:role]
    assert_equal "What's 2+2?", result.messages[0][:content]
    assert_equal "assistant", result.messages[1][:role]
    assert_equal "The answer is 4.", result.messages[1][:content]
    assert result.compacted?
    assert_equal 1, result.stats[:dropped]
  end

  # ── Truncate decisions ───────────────────────────────────────────────

  def test_truncates_result_when_call_kept_but_result_not
    long_result = "x" * 1000
    messages = [
      user_msg("Read the file"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Read", input: { path: "big.rb" })]),
      tool_result_msg(long_result, tool_call_id: "c1"),
      assistant_msg("Done.")
    ]

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.9, keep_result: 0.2 }),
      truncate_head_chars: 100
    )
    result = compactor.compact(messages)

    assert_equal 4, result.messages.size
    # The tool result should be truncated
    truncated_content = result.messages[2][:content]
    assert truncated_content.start_with?("x" * 100)
    assert truncated_content.include?("truncated")
    assert truncated_content.include?("900 chars omitted")
    assert_equal 1, result.stats[:truncated]
  end

  def test_truncated_content_preserves_head
    original = "A" * 500 + "B" * 500
    messages = [
      user_msg("Check"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Read", input: {})]),
      tool_result_msg(original, tool_call_id: "c1"),
      assistant_msg("OK")
    ]

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.9, keep_result: 0.1 }),
      truncate_head_chars: 200
    )
    result = compactor.compact(messages)

    content = result.messages[2][:content]
    assert content.start_with?("A" * 200)
    refute content.include?("B" * 500)
  end

  # ── Mixed decisions ──────────────────────────────────────────────────

  def test_mixed_keep_drop_truncate
    messages = [
      user_msg("Fix the bug"),
      # Call 1: keep both
      assistant_msg("", tool_calls: [
        tool_call(id: "c1", name: "Read", input: { path: "a.rb" })
      ]),
      tool_result_msg("content_a", tool_call_id: "c1"),
      # Call 2: drop both
      assistant_msg("", tool_calls: [
        tool_call(id: "c2", name: "Bash", input: { command: "ls" })
      ]),
      tool_result_msg("file_a.rb\nfile_b.rb", tool_call_id: "c2"),
      # Call 3: truncate
      assistant_msg("", tool_calls: [
        tool_call(id: "c3", name: "Read", input: { path: "b.rb" })
      ]),
      tool_result_msg("content_b_long", tool_call_id: "c3"),
      assistant_msg("Fixed!")
    ]

    provider = provider_with_decisions(
      "c1" => { keep_call: 0.9, keep_result: 0.9 },
      "c2" => { keep_call: 0.1, keep_result: 0.1 },
      "c3" => { keep_call: 0.9, keep_result: 0.2 }
    )

    compactor = Ask::Decisions::Compactor.new(provider, truncate_head_chars: 10)
    result = compactor.compact(messages)

    # c1 kept, c2 dropped, c3 truncated = 8 - 2 (c2 pair) = 6 messages
    assert_equal 6, result.messages.size
    assert_equal 1, result.stats[:kept]
    assert_equal 1, result.stats[:dropped]
    assert_equal 1, result.stats[:truncated]

    # c1 result still intact
    assert_equal "content_a", result.messages[2][:content]
    # c3 result truncated
    assert result.messages[6][:content].start_with?("content_b")
    assert result.messages[6][:content].include?("truncated")
  end

  # ── Pinned messages ──────────────────────────────────────────────────

  def test_first_message_always_pinned
    messages = [
      user_msg("Important instruction: never delete src/"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Bash", input: { command: "ls" })]),
      tool_result_msg("src/ lib/ test/", tool_call_id: "c1"),
      assistant_msg("Done.")
    ]

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.1, keep_result: 0.1 })
    )
    result = compactor.compact(messages)

    # First message always kept
    assert_equal "Important instruction: never delete src/", result.messages[0][:content]
    # But c1 pair should be dropped
    assert_equal 2, result.messages.size
  end

  def test_recent_messages_not_touched
    messages = [
      user_msg("Start"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Read", input: {})]),
      tool_result_msg("old content", tool_call_id: "c1"),
      assistant_msg("Intermediate."),
      assistant_msg("", tool_calls: [tool_call(id: "c2", name: "Read", input: {})]),
      tool_result_msg("recent content", tool_call_id: "c2"),
      user_msg("Done?")
    ]

    # preserve_recent: 3 means the last 3 messages are pinned
    # Messages 4, 5, 6 are pinned. Message 0 is pinned.
    # c2 pair (indices 4, 5) is pinned → always kept
    # c1 pair (indices 1, 2) is NOT pinned → candidate for pruning
    provider = provider_with_decisions(
      "c1" => { keep_call: 0.1, keep_result: 0.1 },
      "c2" => { keep_call: 0.9, keep_result: 0.9 }
    )

    compactor = Ask::Decisions::Compactor.new(provider, preserve_recent: 3)
    result = compactor.compact(messages)

    # c1 should be dropped (not pinned)
    # c2 should be kept (pinned)
    kept_contents = result.messages.map { |m| m[:content] }
    refute kept_contents.include?("old content")
    assert kept_contents.include?("recent content")
  end

  def test_pinned_recent_never_dropped_even_if_jev_says_drop
    messages = [
      user_msg("Start"),
      assistant_msg("OK"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Read", input: {})]),
      tool_result_msg("recent but Jev says drop", tool_call_id: "c1"),
      user_msg("What now?")
    ]

    # preserve_recent: 2 → last 2 messages (index 3, 4) are pinned
    # But wait — c1 is at index 2 (assistant) and result at index 3 (tool)
    # Index 3 is pinned, index 2 is NOT pinned
    # The pair check: if BOTH are pinned, skip. If only one is pinned...
    # Let me re-check the logic.

    # Actually, with preserve_recent: 2, indices 3 and 4 are pinned.
    # Index 0 is always pinned. So pinned = {0, 3, 4}
    # c1 call_msg_idx=2, result_msg_idx=3
    # The pair is NOT fully pinned (2 is not pinned) so it IS evaluated
    # But result is at index 3 which is pinned...

    # In fast-jev-compaction: pinned messages are never touched.
    # A tool result that lives in a pinned message should not be truncated.
    # Let's verify our logic handles this correctly.

    provider = provider_with_decisions(
      "c1" => { keep_call: 0.1, keep_result: 0.1 }
    )

    compactor = Ask::Decisions::Compactor.new(provider, preserve_recent: 2)
    result = compactor.compact(messages)

    # The tool result is in a pinned message (index 3), so it should stay
    kept_contents = result.messages.map { |m| m[:content] }
    assert kept_contents.include?("recent but Jev says drop")
  end

  # ── Multiple tool calls per assistant message ────────────────────────

  def test_multiple_tool_calls_in_one_message
    messages = [
      user_msg("Check both files"),
      assistant_msg("", tool_calls: [
        tool_call(id: "c1", name: "Read", input: { path: "a.rb" }),
        tool_call(id: "c2", name: "Read", input: { path: "b.rb" })
      ]),
      tool_result_msg("content_a", tool_call_id: "c1"),
      tool_result_msg("content_b", tool_call_id: "c2"),
      assistant_msg("Both look good.")
    ]

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
    messages = [
      user_msg("short"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Read", input: {})]),
      tool_result_msg("a" * 500, tool_call_id: "c1"),
      assistant_msg("", tool_calls: [tool_call(id: "c2", name: "Read", input: {})]),
      tool_result_msg("b" * 500, tool_call_id: "c2"),
      assistant_msg("Done")
    ]

    provider = provider_with_decisions(
      "c1" => { keep_call: 0.9, keep_result: 0.9 },
      "c2" => { keep_call: 0.1, keep_result: 0.1 }
    )

    compactor = Ask::Decisions::Compactor.new(provider)
    result = compactor.compact(messages)

    assert_equal 6, result.stats[:messages_before]
    assert result.stats[:messages_after] < 6
    assert_equal 1, result.stats[:kept]
    assert_equal 1, result.stats[:dropped]
    assert_equal 2, result.stats[:tool_pairs_evaluated]
    assert result.stats[:chars_before] > 0
    assert result.stats[:chars_after] < result.stats[:chars_before]
    assert result.stats[:reduction_ratio] > 0
    assert result.stats[:reduction_ratio] < 1
  end

  def test_reduction_ratio_one_when_all_dropped
    messages = [
      user_msg("x"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Bash", input: {})]),
      tool_result_msg("big" * 1000, tool_call_id: "c1"),
      assistant_msg("Done")
    ]

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.1, keep_result: 0.1 })
    )
    result = compactor.compact(messages)

    assert result.stats[:reduction_ratio] > 0.9
  end

  # ── Result object ────────────────────────────────────────────────────

  def test_result_to_s_when_compacted
    messages = [
      user_msg("x"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Bash", input: {})]),
      tool_result_msg("y", tool_call_id: "c1"),
      assistant_msg("z")
    ]

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
    messages = [
      user_msg("Fix it"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Read", input: { path: "a.rb" })]),
      tool_result_msg("a" * 500, tool_call_id: "c1"),
      assistant_msg("Done")
    ]

    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    state = compactor.send(:build_state, messages, compactor.send(:build_pairs, messages))

    conv = state[:conversation]
    # The tool result line should be a placeholder
    assert conv[2].include?("omitted")
    assert conv[2].include?("500 chars")
    # The tool call should include the input
    assert conv[1].include?("Read")
    assert conv[1].include?("a.rb")
  end

  def test_state_includes_goal
    messages = [
      user_msg("Fix the bug"),
      assistant_msg("OK")
    ]

    compactor = Ask::Decisions::Compactor.new(
      Ask::Decisions::Static.new,
      goal: "Fix the failing test in spec/user_spec.rb"
    )
    state = compactor.send(:build_state, messages, [])

    assert_equal "Fix the failing test in spec/user_spec.rb", state[:goal]
  end

  # ── Token estimation ─────────────────────────────────────────────────

  def test_estimate_tokens_basic
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    # "hello" = 5 letters, 5/6 ≈ 1 token
    assert compactor.send(:estimate_tokens, "hello") >= 1
    # Empty string
    assert_equal 0, compactor.send(:estimate_tokens, "")
    assert_equal 0, compactor.send(:estimate_tokens, nil)
  end

  def test_estimate_tokens_with_digits
    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    # "abc123" = 3 letters (0.5) + 3 digits (1.5) + 0 others = 2 tokens
    tokens = compactor.send(:estimate_tokens, "abc123")
    assert tokens >= 2
    assert tokens <= 3
  end

  # ── Batching ─────────────────────────────────────────────────────────

  def test_batching_splits_large_question_sets
    # Create enough tool calls to exceed max_request_tokens
    calls = (1..20).map { |i| tool_call(id: "c#{i}", name: "Read", input: { path: "file_#{i}.rb" }) }
    messages = [
      user_msg("Read all files"),
      assistant_msg("", tool_calls: calls)
    ]
    calls.each do |tc|
      messages.insert(-1, tool_result_msg("content for #{tc[:id]}", tool_call_id: tc[:id]))
    end
    messages << assistant_msg("Done")

    # With a very small max_request_tokens, we force batching
    compactor = Ask::Decisions::Compactor.new(
      Ask::Decisions::Static.new,
      max_request_tokens: 500,
      preserve_recent: 1
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
    # A tool result with no matching tool call
    messages = [
      user_msg("Hi"),
      tool_result_msg("orphan result", tool_call_id: "nonexistent"),
      assistant_msg("Hello!")
    ]

    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    result = compactor.compact(messages)

    # Should not crash, orphan result stays
    assert_equal 3, result.messages.size
    assert result.messages.any? { |m| m[:content] == "orphan result" }
  end

  def test_tool_call_without_result
    # A tool call with no corresponding tool result
    messages = [
      user_msg("Do something"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Bash", input: {})]),
      assistant_msg("I tried.")
    ]

    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    result = compactor.compact(messages)

    # No pairs found, nothing to compact
    assert_equal 3, result.messages.size
    refute result.compacted?
  end

  def test_all_results_dropped_removes_all_tool_messages
    messages = [
      user_msg("Go"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Bash", input: {})]),
      tool_result_msg("result_1", tool_call_id: "c1"),
      assistant_msg("", tool_calls: [tool_call(id: "c2", name: "Bash", input: {})]),
      tool_result_msg("result_2", tool_call_id: "c2"),
      assistant_msg("Done")
    ]

    provider = provider_with_decisions(
      "c1" => { keep_call: 0.1, keep_result: 0.1 },
      "c2" => { keep_call: 0.1, keep_result: 0.1 }
    )

    compactor = Ask::Decisions::Compactor.new(provider)
    result = compactor.compact(messages)

    # Only user and final assistant messages remain
    assert_equal 2, result.messages.size
    assert_equal "Go", result.messages[0][:content]
    assert_equal "Done", result.messages[1][:content]
  end

  def test_short_content_not_truncated_even_if_threshold_met
    messages = [
      user_msg("Read"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Read", input: {})]),
      tool_result_msg("short", tool_call_id: "c1"),
      assistant_msg("OK")
    ]

    compactor = Ask::Decisions::Compactor.new(
      provider_with_decisions("c1" => { keep_call: 0.9, keep_result: 0.1 }),
      truncate_head_chars: 300
    )
    result = compactor.compact(messages)

    # Content is shorter than truncate_head_chars, so it stays intact
    assert_equal "short", result.messages[2][:content]
  end

  # ── normalize / hashify ─────────────────────────────────────────────

  def test_normalize_accepts_object_with_role_and_content
    msg = OpenStruct.new(role: :assistant, content: "hello", tool_calls: nil, tool_call_id: nil)
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
    # Exactly at threshold
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
    messages = [
      user_msg("Fix the failing test in user_spec.rb"),
      # Step 1: Read the test file — relevant, keep
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Read", input: { path: "test/user_spec.rb" })]),
      tool_result_msg("require 'spec_helper'\ndescribe User do\n  it 'validates email' do\n    expect(User.new(email: nil)).not_to be_valid\n  end\nend", tool_call_id: "c1"),
      # Step 2: List files — exploratory, drop
      assistant_msg("", tool_calls: [tool_call(id: "c2", name: "Bash", input: { command: "ls -la" })]),
      tool_result_msg("total 48\ndrwxr-xr-x  8 user  staff  256 Sep 18\n-rw-r--r--  1 user  staff  1024 Sep 18 user_spec.rb", tool_call_id: "c2"),
      # Step 3: Read the model — relevant, keep
      assistant_msg("", tool_calls: [tool_call(id: "c3", name: "Read", input: { path: "app/models/user.rb" })]),
      tool_result_msg("class User < ApplicationRecord\n  validates :email, presence: true\nend", tool_call_id: "c3"),
      # Step 4: Check git status — exploratory, drop
      assistant_msg("", tool_calls: [tool_call(id: "c4", name: "Bash", input: { command: "git status" })]),
      tool_result_msg("On branch main\nnothing to commit, working tree clean", tool_call_id: "c4"),
      assistant_msg("The test expects email validation to work. Let me check the model...")
    ]

    provider = provider_with_decisions(
      "c1" => { keep_call: 0.9, keep_result: 0.9 },  # Read test — relevant
      "c2" => { keep_call: 0.2, keep_result: 0.1 },  # ls — exploratory
      "c3" => { keep_call: 0.9, keep_result: 0.9 },  # Read model — relevant
      "c4" => { keep_call: 0.2, keep_result: 0.1 }   # git status — exploratory
    )

    compactor = Ask::Decisions::Compactor.new(provider, preserve_recent: 2)
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
    # The Static provider defaults to noul: 0.5 for Noul questions
    # With keep_threshold: 0.5, 0.5 >= 0.5 → keep
    messages = [
      user_msg("Go"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Bash", input: {})]),
      tool_result_msg("result", tool_call_id: "c1"),
      assistant_msg("Done")
    ]

    compactor = Ask::Decisions::Compactor.new(Ask::Decisions::Static.new)
    result = compactor.compact(messages)

    # Default noul is 0.5, threshold is 0.5 → all kept
    assert_equal 4, result.messages.size
    assert_equal 1, result.stats[:kept]
  end

  def test_custom_keep_threshold
    messages = [
      user_msg("Go"),
      assistant_msg("", tool_calls: [tool_call(id: "c1", name: "Bash", input: {})]),
      tool_result_msg("result", tool_call_id: "c1"),
      assistant_msg("Done")
    ]

    # Default noul is 0.5, threshold 0.6 → 0.5 < 0.6 → drop
    compactor = Ask::Decisions::Compactor.new(
      Ask::Decisions::Static.new,
      keep_threshold: 0.6
    )
    result = compactor.compact(messages)

    assert_equal 2, result.messages.size
    assert_equal 1, result.stats[:dropped]
  end
end
