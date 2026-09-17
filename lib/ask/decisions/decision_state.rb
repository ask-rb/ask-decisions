# frozen_string_literal: true

module Ask
  module Decisions
    # Projects session state into a compact document for Jev. Filters out
    # irrelevant fields, truncates to a token budget, and produces the
    # structured state that System One models expect.
    #
    # Jev degrades with irrelevant detail ("context rot"), so the
    # projection layer is the single most important piece of the
    # integration: it determines accuracy by deciding what the model sees.
    #
    #   state = Ask::Decisions::DecisionState.build(
    #     user_turn: "check the weather in seattle tomorrow",
    #     recent_turns: [...],
    #     tools: [...],
    #     plan: "Investigate the weather API...",
    #     budget: 8000
    #   )
    #
    class DecisionState
      # Approximate chars per token (conservative for mixed content).
      CHARS_PER_TOKEN = 4

      # Build a compact state document from session components.
      #
      # @param user_turn [String] the latest user message
      # @param recent_turns [Array<Hash>, nil] recent conversation messages
      # @param tools [Array<Hash>, nil] tool roster (name + description)
      # @param agent_roster [Array<Hash>, nil] available agents
      # @param plan [String, nil] current plan/task description
      # @param memory [Array<String>, nil] relevant memory entries
      # @param todos [Array<Hash>, nil] current todo items
      # @param budget [Integer] max characters for the state
      # @return [Hash] the projected state
      def self.build(
        user_turn:,
        recent_turns: nil,
        tools: nil,
        agent_roster: nil,
        plan: nil,
        memory: nil,
        todos: nil,
        budget: 32_000 * CHARS_PER_TOKEN
      )
        state = {}
        remaining = budget

        # Always include the user turn (highest priority).
        truncated_turn = truncate(user_turn, remaining - 100)
        state[:user_turn] = truncated_turn
        remaining -= truncated_turn.length

        # Add recent turns if there's budget.
        if recent_turns && remaining > 500
          recent = truncate_messages(recent_turns, remaining / 2)
          state[:recent_turns] = recent
          remaining -= recent.to_s.length
        end

        # Add tools if there's budget.
        if tools && remaining > 200
          tool_summary = tools.map do |t|
            name = t[:name] || t["name"]
            desc = t[:description] || t["description"] || ""
            "#{name}: #{truncate(desc, 80)}"
          end
          state[:available_tools] = tool_summary
          remaining -= tool_summary.to_s.length
        end

        # Add plan if there's budget.
        if plan && remaining > 100
          state[:plan] = truncate(plan, remaining / 3)
          remaining -= state[:plan].length
        end

        # Add memory if there's budget.
        if memory && remaining > 100
          state[:memory] = memory.first(5).map { |m| truncate(m, 200) }
          remaining -= state[:memory].to_s.length
        end

        # Add todos if there's budget.
        if todos && remaining > 100
          state[:todos] = todos.first(10).map do |t|
            { task: t[:task] || t["task"], status: t[:status] || t["status"] }
          end
          remaining -= state[:todos].to_s.length
        end

        state
      end

      # Truncate a string to a character budget.
      def self.truncate(str, limit)
        return "" if str.nil?
        str = str.to_s
        return str if str.length <= limit
        "#{str[0, limit - 20]}…[#{str.length - limit + 20} chars elided]"
      end

      # Truncate an array of messages to fit within a character budget,
      # keeping the most recent messages first.
      def self.truncate_messages(messages, budget)
        return [] if messages.nil? || messages.empty?
        result = []
        used = 0
        # Walk from most recent to oldest.
        messages.reverse_each do |msg|
          text = msg[:content] || msg["content"] || msg.to_s
          entry = { role: msg[:role] || msg["role"], content: truncate(text, 2000) }
          entry_len = entry.to_s.length
          break if used + entry_len > budget
          result.unshift(entry)
          used += entry_len
        end
        result
      end
    end
  end
end
