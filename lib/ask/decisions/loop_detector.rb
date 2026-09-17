# frozen_string_literal: true

module Ask
  module Decisions
    # Detects agent loops using Jev — whether the agent is repeating itself,
    # making progress, or stuck. Replaces the naive exact-match ×3 approach
    # with a judgment over the conversation trajectory.
    #
    #   detector = Ask::Decisions::LoopDetector.new(provider)
    #   verdict = detector.check(
    #     recent_turns: [...],
    #     current_tool: "bash",
    #     current_args: { command: "npm test" },
    #     turn_count: 8
    #   )
    #   verdict.stuck?       # => true
    #   verdict.progressing?  # => false
    #   verdict.advice        # => "repeat"
    #
    class LoopDetector
      QUESTIONS = {
        repeating: Ask::Decision::Noul.new(
          instructions: "Is the assistant repeating the same action or producing the same output as in the recent conversation?"
        ),
        stuck: Ask::Decision::Noul.new(
          instructions: "Is the assistant stuck — unable to make progress on the user's request?"
        ),
        progress: Ask::Decision::Score.new(
          instructions: "How much progress has the assistant made toward completing the user's request?",
          criteria: [
            "No progress — same state as before",
            "Minimal — tried something but it failed or was undone",
            "Some — partially addressed the request",
            "Significant — most of the work is done",
            "Complete — the request appears to be fulfilled"
          ]
        )
      }.freeze

      # Thresholds for loop detection.
      STUCK_THRESHOLD = 0.7     # noul >= 0.7 means stuck
      REPEAT_THRESHOLD = 0.7    # noul >= 0.7 means repeating
      PROGRESS_THRESHOLD = 1.5  # score < 1.5 means little progress

      # @param provider [Ask::DecisionProvider]
      def initialize(provider)
        @provider = provider
      end

      # Check whether the agent is looping or stuck.
      #
      # @param recent_turns [Array<Hash>] recent conversation messages
      # @param current_tool [String, nil] the tool being called now
      # @param current_args [Hash, nil] its arguments
      # @param turn_count [Integer] how many turns have happened
      # @return [LoopVerdict]
      def check(recent_turns:, current_tool: nil, current_args: nil, turn_count: 0)
        state = build_state(
          recent_turns: recent_turns,
          current_tool: current_tool,
          current_args: current_args,
          turn_count: turn_count
        )

        result = @provider.evaluate(state: state, decisions: QUESTIONS)
        LoopVerdict.new(result)
      end

      private

      def build_state(recent_turns:, current_tool:, current_args:, turn_count:)
        state = {
          turn_count: turn_count,
          recent_actions: extract_actions(recent_turns)
        }
        if current_tool
          state[:current_tool] = current_tool
          state[:current_args] = current_args
        end
        state
      end

      def extract_actions(turns)
        return [] unless turns
        turns.last(6).filter_map do |turn|
          next unless turn[:tool_calls] || turn["tool_calls"]
          calls = turn[:tool_calls] || turn["tool_calls"]
          Array(calls).map do |call|
            name = call[:name] || call["name"]
            args = call[:arguments] || call["arguments"] || {}
            "#{name}(#{args.keys.join(', ')})"
          end
        end.flatten
      end

      # Verdict from loop detection.
      class LoopVerdict
        attr_reader :result

        def initialize(result)
          @result = result
        end

        def repeating?
          noul = @result["repeating"]
          noul && noul.noul >= REPEAT_THRESHOLD
        end

        def stuck?
          noul = @result["stuck"]
          noul && noul.noul >= STUCK_THRESHOLD
        end

        def progress_score
          score = @result["progress"]
          score&.score || 0.0
        end

        def progressing?
          progress_score >= PROGRESS_THRESHOLD
        end

        # The recommended action based on the verdict.
        def advice
          return "stop" if repeating? && !progressing?
          return "pivot" if stuck?
          return "continue" if progressing?
          "monitor"
        end

        def to_s
          parts = []
          parts << "repeating" if repeating?
          parts << "stuck" if stuck?
          parts << "progress: #{('%.1f' % progress_score)}"
          parts << "→ #{advice}"
          parts.join(", ")
        end
      end
    end
  end
end
