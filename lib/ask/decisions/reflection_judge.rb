# frozen_string_literal: true

module Ask
  module Decisions
    # Decision-based reflection — replaces the LLM self-critique with a
    # simple Noul: "is there a concrete, actionable improvement?"
    #
    #   judge = Ask::Decisions::ReflectionJudge.new(provider)
    #   verdict = judge.reflect(
    #     request: "Fix the bug in login.rb",
    #     response: "I found the issue...",
    #     attempt: 2
    #   )
    #   verdict.improve?  # => true
    #   verdict.done?     # => false
    #
    class ReflectionJudge
      QUESTIONS = {
        has_improvement: Ask::Decision::Noul.new(
          instructions: "Is there a concrete, actionable improvement that would make this response better for the user?"
        ),
        quality: Ask::Decision::Score.new(
          instructions: "How close is this response to being fully satisfactory?",
          criteria: [
            "Poor — major issues remain",
            "Fair — some improvements possible",
            "Good — minor polish only",
            "Excellent — ready to deliver"
          ]
        )
      }.freeze

      # @param provider [Ask::DecisionProvider]
      # @param max_reflections [Integer] stop after this many improvement rounds
      def initialize(provider, max_reflections: 3)
        @provider = provider
        @max_reflections = max_reflections
      end

      # Decide whether to improve or stop.
      #
      # @param request [String] the original user request
      # @param response [String] the current response
      # @param attempt [Integer] which reflection round (1-based)
      # @return [ReflectionVerdict]
      def reflect(request:, response:, attempt: 1)
        state = { request: request, response: response, attempt: attempt }
        result = @provider.evaluate(state: state, decisions: QUESTIONS)
        ReflectionVerdict.new(result, attempt, @max_reflections)
      end

      # Verdict from reflection.
      class ReflectionVerdict
        attr_reader :result, :attempt, :max_reflections

        def initialize(result, attempt, max_reflections)
          @result = result
          @attempt = attempt
          @max_reflections = max_reflections
        end

        def improve?
          noul = @result["has_improvement"]
          quality = @result["quality"]
          # Improve if there's a concrete improvement AND quality isn't excellent
          (noul&.noul || 0) >= 0.5 && (quality&.score || 0) < 3.5
        end

        def done?
          !improve? || attempt >= @max_reflections
        end

        def quality_score
          @result["quality"]&.score || 0.0
        end

        def to_s
          done? ? "done (quality: #{('%.1f' % quality_score)})" : "improve (quality: #{('%.1f' % quality_score)})"
        end
      end
    end
  end
end
