# frozen_string_literal: true

module Ask
  module Decisions
    # Decision-based conversation compactor. Replaces lossy summarization with
    # Jev-scored pruning: every tool call and result is evaluated for relevance,
    # and the irrelevant ones are dropped or truncated — everything kept stays
    # verbatim.
    #
    # This is the Ruby equivalent of the fast-jev-compaction approach: rather
    # than asking an LLM to summarize old turns (which loses file paths, exact
    # errors, constraints, and command details), Jev scores each tool call and
    # result independently, and the compactor applies three-tier decisions.
    #
    #   compactor = Ask::Decisions::Compactor.new(provider)
    #   result = compactor.compact(messages)
    #   result.messages   # => pruned message list
    #   result.stats      # => { kept: 12, dropped: 5, truncated: 3, ... }
    #   result.reduction_ratio  # => 0.29 (29% of tool content removed)
    #
    # Message format (hashes):
    #
    #   { role: "user", content: "Fix the failing test" }
    #   { role: "assistant", content: "",
    #     tool_calls: [{ id: "call_1", name: "Read", input: { path: "src/a.rb" } }] }
    #   { role: "tool", content: "file contents...",
    #     tool_call_id: "call_1" }
    #
    # The first message is always kept. The most recent +preserve_recent+
    # messages are never touched. Everything else is a candidate for pruning.
    #
    class Compactor
      # Approximate chars per token for budget calculations.
      CHARS_PER_TOKEN = 4

      # Jev Noul questions asked per tool call.
      CALL_QUESTION = "Should this tool call be kept — does knowing it was " \
                       "made still matter for the current conversation?"
      RESULT_QUESTION = "Should this tool result be kept verbatim — are its " \
                         "contents still needed and would re-running the tool " \
                         "not suffice?"

      # @param provider [Ask::DecisionProvider] the Jev/decision provider
      # @param keep_threshold [Float] minimum Noul probability to keep (0.0–1.0)
      # @param preserve_recent [Integer] newest messages never touched
      # @param max_state_tokens [Integer] token ceiling for state sent to Jev
      # @param max_request_tokens [Integer] token ceiling per batch request
      # @param truncate_head_chars [Integer] chars retained from dropped results
      # @param goal [String, nil] ongoing task description for Jev context
      def initialize(provider,
                     keep_threshold: 0.5,
                     preserve_recent: 4,
                     max_state_tokens: 25_000,
                     max_request_tokens: 30_000,
                     truncate_head_chars: 300,
                     goal: nil)
        @provider = provider
        @keep_threshold = keep_threshold
        @preserve_recent = preserve_recent
        @max_state_tokens = max_state_tokens
        @max_request_tokens = max_request_tokens
        @truncate_head_chars = truncate_head_chars
        @goal = goal
      end

      # Compact a conversation by scoring every tool call and result with Jev,
      # then dropping or truncating the irrelevant ones.
      #
      # @param messages [Array<Hash>] conversation messages
      # @return [Result] compacted messages and stats
      def compact(messages)
        messages = normalize(messages)
        return Result.new(messages.dup, original_count: messages.size) if messages.size < 2

        pairs = build_pairs(messages)
        pinned = compute_pinned(messages)

        return Result.new(messages.dup, original_count: messages.size) if pairs.empty?

        state = build_state(messages, pairs)
        questions = build_questions(pairs, pinned)
        batch = batch_and_execute(state, questions)
        decisions = extract_decisions(batch, pairs)
        mark_pinned_pairs(decisions, pairs, pinned)
        pruned = apply_decisions(messages, decisions, pinned)
        stats = compute_stats(messages, pruned, decisions)

        Result.new(pruned, stats: stats, original_count: messages.size)
      end

      private

      # ── Normalization ────────────────────────────────────────────────

      def normalize(messages)
        Array(messages).map { |m| m.is_a?(Hash) ? m : hashify(m) }
      end

      def hashify(msg)
        {
          role: msg.respond_to?(:role) ? msg.role.to_s : "unknown",
          content: msg.respond_to?(:content) ? msg.content.to_s : msg.to_s,
          tool_calls: extract_tool_calls_from_object(msg),
          tool_call_id: msg.respond_to?(:tool_call_id) ? msg.tool_call_id : nil
        }.compact
      end

      def extract_tool_calls_from_object(msg)
        return nil unless msg.respond_to?(:tool_calls) && msg.tool_calls
        Array(msg.tool_calls).map do |tc|
          {
            id: tc.respond_to?(:id) ? tc.id : tc[:id],
            name: tc.respond_to?(:name) ? tc.name : tc[:name],
            input: tc.respond_to?(:arguments) ? tc.arguments : (tc[:input] || tc[:arguments])
          }
        end
      end

      # ── Pairing ──────────────────────────────────────────────────────

      # Group messages into tool_call / tool_result pairs by tool_call_id.
      # Returns an array of { call_msg:, result_msg:, call: } hashes.
      def build_pairs(messages)
        call_index = {}
        messages.each_with_index do |msg, idx|
          Array(msg[:tool_calls]).each do |tc|
            call_index[tc[:id]] = { call_msg_idx: idx, call: tc }
          end
        end

        pairs = []
        messages.each_with_index do |msg, idx|
          tcid = msg[:tool_call_id]
          next unless tcid && call_index[tcid]

          entry = call_index[tcid]
          pairs << {
            call_msg_idx: entry[:call_msg_idx],
            result_msg_idx: idx,
            call: entry[:call],
            call_id: tcid
          }
        end

        pairs.sort_by { |p| p[:call_msg_idx] }
      end

      # First message and the most recent +preserve_recent+ messages are pinned.
      # Pinned messages are never removed, and a pair living entirely inside
      # them is never scored — Jev does not see pinned content.
      def compute_pinned(messages)
        pinned = Set.new([0])
        start = [messages.size - @preserve_recent, 1].max
        (start...messages.size).each { |i| pinned.add(i) }
        pinned
      end

      # ── State ────────────────────────────────────────────────────────

      # Build the state Jev sees: full conversation with tool results replaced
      # by short placeholder notes. Tool inputs are included, text is included,
      # nothing is summarized.
      def build_state(messages, pairs)
        result_index = {}
        pairs.each { |p| result_index[p[:result_msg_idx]] = p }

        lines = messages.each_with_index.map do |msg, idx|
          content = msg[:content].to_s

          if result_index[idx]
            result_index[idx][:result_preview] = content
            chars = content.length
            "[tool result: ok, #{chars} chars (omitted)]"
          elsif msg[:tool_calls] && !msg[:tool_calls].empty?
            tc_strs = msg[:tool_calls].map do |tc|
              input_str = format_input(tc[:input])
              "#{tc[:name]}(#{input_str})"
            end
            tc_strs.empty? ? content : "#{content}\n#{tc_strs.join("\n")}"
          else
            content
          end
        end

        { conversation: lines, goal: @goal }.compact
      end

      def format_input(input)
        return "" unless input
        str = input.is_a?(String) ? input : JSON.generate(input)
        str.length > 100 ? "#{str[0, 100]}..." : str
      end

      # ── Questions ────────────────────────────────────────────────────

      def build_questions(pairs, pinned)
        questions = {}
        pairs.each do |pair|
          # Skip pairs where both the call and result live in pinned messages.
          # Pinned messages are never touched — Jev does not score them.
          next if pinned.include?(pair[:call_msg_idx]) && pinned.include?(pair[:result_msg_idx])

          call_id = pair[:call_id]
          tc = pair[:call]
          input_str = format_input(tc[:input])

          questions["keep_call_#{call_id}"] = Ask::Decision::Noul.new(
            instructions: "#{CALL_QUESTION}\n\nTool: #{tc[:name]}\nInput: #{input_str}"
          )
          questions["keep_result_#{call_id}"] = Ask::Decision::Noul.new(
            instructions: "#{RESULT_QUESTION}\n\nTool: #{tc[:name]}\nInput: #{input_str}"
          )
        end
        questions
      end

      # ── Batching ─────────────────────────────────────────────────────

      # Split questions into batches that fit the request token budget,
      # send each batch concurrently (sequentially in Ruby, but the same
      # pattern as fast-jev-compaction), and merge results.
      def batch_and_execute(state, questions)
        return empty_batch if questions.empty?

        batches = partition_batches(state, questions)
        return execute_batch(state, questions) if batches.size <= 1

        results = batches.map { |batch| execute_batch(state, batch) }
        merge_batches(results)
      end

      def partition_batches(state, questions)
        state_tokens = estimate_tokens(JSON.generate(state))
        pairs = questions.to_a
        batches = []
        current = {}
        current_tokens = state_tokens

        pairs.each do |id, decision|
          q_tokens = estimate_tokens(JSON.generate(decision.to_h))
          if current_tokens + q_tokens > @max_request_tokens && current.any?
            batches << current
            current = {}
            current_tokens = state_tokens
          end
          current[id] = decision
          current_tokens += q_tokens
        end

        batches << current if current.any?
        batches
      end

      def execute_batch(state, questions)
        @provider.evaluate(
          state: JSON.generate(state),
          decisions: questions
        )
      end

      def empty_batch
        Ask::DecisionResult::Batch.new(answers: {})
      end

      def merge_batches(batches)
        merged = {}
        batches.each do |batch|
          batch.answers.each { |k, v| merged[k] = v }
        end
        Ask::DecisionResult::Batch.new(answers: merged)
      end

      # ── Decisions ────────────────────────────────────────────────────

      # A pair whose call and result both live in pinned messages was never
      # scored. Record that as its own action so the stats describe Jev's
      # work, not the pinning.
      def mark_pinned_pairs(decisions, pairs, pinned)
        pairs.each do |pair|
          next unless pinned.include?(pair[:call_msg_idx]) && pinned.include?(pair[:result_msg_idx])

          if (decision = decisions[pair[:call_id]])
            decision[:action] = :pinned
          end
        end
      end

      def extract_decisions(batch, pairs)
        decisions = {}
        pairs.each do |pair|
          call_id = pair[:call_id]
          keep_call_answer = batch["keep_call_#{call_id}"]
          keep_result_answer = batch["keep_result_#{call_id}"]

          keep_call = keep_call_answer&.noul || 0.0
          keep_result = keep_result_answer&.noul || 0.0

          decisions[call_id] = {
            keep_call: keep_call,
            keep_result: keep_result,
            action: classify_action(keep_call, keep_result)
          }
        end
        decisions
      end

      # Three-tier decision classification.
      def classify_action(keep_call, keep_result)
        if keep_result >= @keep_threshold
          :keep
        elsif keep_call >= @keep_threshold
          :truncate
        else
          :drop
        end
      end

      # ── Apply ────────────────────────────────────────────────────────

      def apply_decisions(messages, decisions, pinned)
        pairs = build_pairs(messages)
        remove_indices = Set.new
        truncate_indices = {}
        # call_id => true when the call survives although its result does not
        # (a :drop whose result is pinned downgrades to keeping the call).
        dropped_results = Set.new

        pairs.each do |pair|
          decision = decisions[pair[:call_id]]
          next unless decision

          case decision[:action]
          when :drop
            call_pinned = pinned.include?(pair[:call_msg_idx])
            result_pinned = pinned.include?(pair[:result_msg_idx])

            if call_pinned || result_pinned
              # A result is never left without its call, and a pinned message
              # is never removed. A drop touching a pinned message keeps the
              # pair — the call verbatim, the result truncated to its head.
              if result_pinned
                decision[:action] = :keep
              else
                truncate_indices[pair[:result_msg_idx]] = pair[:call]
                decision[:action] = :truncate
              end
              next
            end

            remove_indices.add(pair[:result_msg_idx])
            dropped_results.add(pair[:call_id])
          when :truncate
            truncate_indices[pair[:result_msg_idx]] = pair[:call]
          end
        end

        messages.each_with_index.filter_map do |msg, idx|
          next if remove_indices.include?(idx)

          if truncate_indices[idx]
            truncate_message(msg, truncate_indices[idx])
          else
            prune_dropped_calls(msg, dropped_results)
          end
        end
      end

      # A drop removes the tool result message; the call itself leaves the
      # assistant message that carried it. A message survives when it has text
      # or surviving calls — it is removed only when the drop empties it.
      def prune_dropped_calls(msg, dropped_results)
        return msg unless msg[:tool_calls] && dropped_results.any?

        surviving = msg[:tool_calls].reject { |tc| dropped_results.include?(tc[:id]) }
        return msg if surviving.size == msg[:tool_calls].size

        if surviving.empty? && msg[:content].to_s.empty?
          nil
        elsif surviving.empty?
          msg.except(:tool_calls)
        else
          msg.merge(tool_calls: surviving)
        end
      end

      def truncate_message(msg, call)
        original = msg[:content].to_s
        return msg if original.length <= @truncate_head_chars

        head = original[0, @truncate_head_chars]
        truncated_content = "#{head}\n...[result truncated: #{original.length - @truncate_head_chars} chars omitted — #{call[:name]} result was kept as call-only]"
        msg.merge(content: truncated_content)
      end

      # ── Stats ────────────────────────────────────────────────────────

      def compute_stats(original, pruned, decisions)
        action_counts = decisions.values.map { |d| d[:action] }.tally
        original_chars = original.sum { |m| m[:content].to_s.length }
        pruned_chars = pruned.sum { |m| m[:content].to_s.length }

        {
          messages_before: original.size,
          messages_after: pruned.size,
          kept: action_counts[:keep] || 0,
          truncated: action_counts[:truncate] || 0,
          dropped: action_counts[:drop] || 0,
          pinned: action_counts[:pinned] || 0,
          tool_pairs_evaluated: decisions.size - (action_counts[:pinned] || 0),
          chars_before: original_chars,
          chars_after: pruned_chars,
          reduction_ratio: original_chars > 0 ? (1.0 - pruned_chars.to_f / original_chars) : 0.0
        }
      end

      # ── Token estimation ─────────────────────────────────────────────

      def estimate_tokens(text)
        str = text.to_s
        letters = str.count("a-zA-Z")
        digits = str.count("0-9")
        others = str.length - letters - digits
        (letters / 6.0 + digits / 2.0 + others).ceil
      end

      # ── Batch result ─────────────────────────────────────────────────

      def extract_call_id(answer_id, prefix)
        answer_id.to_s.sub(/\A#{prefix}/, "")
      end

      # ── Result ───────────────────────────────────────────────────────

      # Holds the compacted messages and compaction statistics.
      class Result
        attr_reader :messages, :stats, :original_count

        def initialize(messages, stats: {}, original_count: nil)
          @messages = messages
          @stats = stats
          @original_count = original_count || messages.size
        end

        # Fraction of tool content removed (0.0 = nothing removed, 1.0 = everything).
        def reduction_ratio
          stats[:reduction_ratio] || 0.0
        end

        # Whether any tool calls were dropped or truncated.
        def compacted?
          (stats[:dropped] || 0) > 0 || (stats[:truncated] || 0) > 0
        end

        def to_s
          if compacted?
            "compacted #{stats[:messages_before]}→#{stats[:messages_after]} messages " \
            "(#{stats[:dropped]} dropped, #{stats[:truncated]} truncated, " \
            "#{(reduction_ratio * 100).round(1)}% reduction)"
          else
            "no compaction needed (#{original_count} messages)"
          end
        end
      end
    end
  end
end
