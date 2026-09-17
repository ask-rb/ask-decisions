# frozen_string_literal: true

module Ask
  module Decisions
    # Routes a user turn to the right tool by asking Jev to pick from the
    # tool roster. Emits the same shape as a tool call so the existing
    # ToolExecutor can run it unchanged.
    #
    #   router = Ask::Decisions::ToolRouter.new(provider, tools: tool_roster)
    #   result = router.route(
    #     user_turn: "check the weather in seattle tomorrow",
    #     recent_turns: [...]
    #   )
    #   result.tool      # => "web_search"
    #   result.confidence  # => 0.92
    #   result.answer_directly?  # => false
    #
    class ToolRouter
      # Non-tool outcomes that the Choice question includes.
      NON_TOOL_OUTCOMES = {
        "answer_directly" => "Answer the user directly without calling any tool",
        "ask_clarifying_question" => "Ask the user a clarifying question before acting",
        "none" => "No action needed; the turn is a follow-up or acknowledgment"
      }.freeze

      # @param provider [Ask::DecisionProvider]
      # @param tools [Array<Hash>] tool roster, each with "name" and "description"
      # @param none_threshold [Float] below this confidence, fall back to LLM
      # @param criteria [Hash, nil] routing-grade descriptions, tool name =>
      #   when to choose it. Worth supplying whenever the roster holds tools
      #   that overlap: a tool's own description is written for the model that
      #   already holds it, and two accurate descriptions can still fail to
      #   separate their tools from the outside. Omitted, each tool's own
      #   description is used.
      # @param limit [Integer] characters kept per description
      def initialize(provider, tools:, none_threshold: 0.5, criteria: nil, limit: 160)
        @provider = provider
        @tools = tools
        @none_threshold = none_threshold
        @criteria = criteria
        @limit = limit
      end

      # Route a user turn to a tool or non-tool outcome.
      #
      # @param user_turn [String] the latest user message
      # @param recent_turns [String, nil] recent conversation context (truncated)
      # @param model [String, nil] model override
      # @return [RouteResult]
      def route(user_turn:, recent_turns: nil, model: nil)
        state = build_state(user_turn: user_turn, recent_turns: recent_turns)
        question = build_question
        result = @provider.evaluate(
          state: state,
          decisions: { "tool.route" => question },
          model: model
        )
        RouteResult.new(result["tool.route"])
      end

      private

      def build_state(user_turn:, recent_turns: nil)
        state = { user_turn: user_turn }
        state[:recent_turns] = truncate(recent_turns, 2000) if recent_turns
        state
      end

      def build_question
        criteria = {}
        @tools.each do |t|
          name = t[:name] || t["name"]
          desc = @criteria&.dig(name) || @criteria&.dig(name.to_s) ||
                 t[:description] || t["description"] || ""
          criteria[name] = truncate(desc, @limit)
        end
        criteria.merge!(NON_TOOL_OUTCOMES)

        Ask::Decision::Choice.new(
          instructions: "Which tool should the assistant use to handle the user's latest request? " \
                        "If no tool is needed, pick answer_directly, ask_clarifying_question, or none.",
          criteria: criteria
        )
      end

      def truncate(str, limit)
        return "" if str.nil?
        str.length > limit ? "#{str[0, limit]}…" : str
      end

      # Result of routing.
      class RouteResult
        attr_reader :choice_answer

        def initialize(choice_answer)
          @choice_answer = choice_answer
        end

        # The selected tool name or non-tool outcome.
        def tool = choice_answer&.choice

        def confidence = choice_answer&.confidence

        def probabilities = choice_answer&.probabilities

        # Should we call a tool, or handle this differently?
        def answer_directly?  = tool == "answer_directly"
        def ask_clarifying?   = tool == "ask_clarifying_question"
        def no_action?        = tool == "none"
        def call_tool?        = !answer_directly? && !ask_clarifying? && !no_action?

        # Is the confidence above the threshold for autonomous action?
        def confident?(threshold = nil)
          threshold ||= 0.7
          return false if confidence.nil?
          confidence >= threshold
        end

        # Should we fall back to the LLM loop?
        def fallback?(none_threshold = 0.5)
          confidence.nil? || confidence < none_threshold
        end

        def to_s
          if call_tool?
            "tool: #{tool} (#{('%.2f' % (confidence || 0))})"
          else
            "#{tool} (#{('%.2f' % (confidence || 0))})"
          end
        end
      end
    end
  end
end
