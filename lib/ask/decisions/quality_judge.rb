# frozen_string_literal: true

module Ask
  module Decisions
    # Decision-based quality judge — replaces the LLM-as-judge evaluator
    # with calibrated Jev scores. Uses composite scoring across rubric
    # dimensions plus a verdict choice.
    #
    #   judge = Ask::Decisions::QualityJudge.new(provider)
    #   verdict = judge.evaluate(
    #     request: "What's the weather in Seattle?",
    #     response: "It's 72°F and sunny in Seattle today.",
    #     rubric: { accuracy: "Is the answer factually correct?", completeness: "Does it fully address the request?" }
    #   )
    #   verdict.accepted?  # => true
    #   verdict.scores     # => { accuracy: 4.0, completeness: 3.5 }
    #
    class QualityJudge
      # Default rubric dimensions.
      DEFAULT_RUBRIC = {
        accuracy: "Is the answer factually correct and free of hallucinations?",
        completeness: "Does the answer fully address the user's request?",
        clarity: "Is the answer clear, well-organized, and easy to understand?"
      }.freeze

      # @param provider [Ask::DecisionProvider]
      def initialize(provider)
        @provider = provider
      end

      # Evaluate a response against a rubric.
      #
      # @param request [String] the original user request
      # @param response [String] the assistant's response
      # @param rubric [Hash{Symbol => String}] dimension → instruction
      # @param threshold [Float] minimum weighted score to accept
      # @return [QualityVerdict]
      def evaluate(request:, response:, rubric: DEFAULT_RUBRIC, threshold: 2.5)
        questions = {}
        rubric.each do |dim, instruction|
          questions[dim.to_s] = Ask::Decision::Score.new(
            instructions: instruction,
            criteria: [
              "Poor — factually wrong, incomplete, or unclear",
              "Fair — partially correct but missing key aspects",
              "Good — correct and complete, minor issues only",
              "Excellent — thorough, accurate, and well-presented"
            ]
          )
        end

        questions["verdict"] = Ask::Decision::Choice.new(
          instructions: "Should this response be accepted, revised, or blocked?",
          criteria: {
            "accept" => "The response is good enough to deliver to the user",
            "revise" => "The response has issues that can be fixed with minor edits",
            "block" => "The response is fundamentally wrong or harmful and must be regenerated"
          }
        )

        state = { request: request, response: response }
        result = @provider.evaluate(state: state, decisions: questions)

        QualityVerdict.new(result, rubric.keys, threshold)
      end

      # Verdict from quality evaluation.
      class QualityVerdict
        attr_reader :result, :scores, :verdict, :threshold

        def initialize(result, dimensions, threshold)
          @result = result
          @threshold = threshold
          @scores = {}

          dimensions.each do |dim|
            answer = result[dim.to_s]
            @scores[dim] = answer&.score || 0.0
          end

          verdict_answer = result["verdict"]
          @verdict = verdict_answer&.choice || "accept"
        end

        def accepted?  = @verdict == "accept"
        def revised?   = @verdict == "revise"
        def blocked?   = @verdict == "block"

        # Weighted average score across dimensions.
        def average_score
          return 0.0 if @scores.empty?
          @scores.values.sum / @scores.size
        end

        # Should the response be accepted based on the score threshold?
        def score_accepts?
          average_score >= @threshold
        end

        def to_s
          scores_str = @scores.map { |k, v| "#{k}: #{('%.1f' % v)}" }.join(", ")
          "#{@verdict} (#{scores_str}, avg: #{('%.1f' % average_score)})"
        end
      end
    end
  end
end
