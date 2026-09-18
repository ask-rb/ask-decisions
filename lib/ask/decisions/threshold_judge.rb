# frozen_string_literal: true

module Ask
  module Decisions
    # Binary accept/reject judge — simpler than QualityJudge when you
    # just need "does this pass?" without a full rubric. Runs a single
    # Noul question and thresholds the result.
    #
    #   judge = Ask::Decisions::ThresholdJudge.new(provider)
    #   verdict = judge.evaluate(
    #     subject: "The code changes look correct and have tests.",
    #     question: "Is this code change safe to merge?"
    #   )
    #   verdict.passed?  # => true
    #   verdict.confidence  # => 0.92
    #
    # Use QualityJudge when you need multi-dimensional scoring.
    # Use ThresholdJudge when you need a fast binary gate.
    #
    class ThresholdJudge
      # @param provider [Ask::DecisionProvider]
      def initialize(provider)
        @provider = provider
      end

      # Evaluate a subject against a yes/no question.
      #
      # @param subject [String] the content to evaluate
      # @param question [String] the yes/no question
      # @param threshold [Float] minimum noul value to pass (default 0.7)
      # @return [ThresholdVerdict]
      def evaluate(subject:, question:, threshold: 0.7)
        decisions = {
          "verdict" => Ask::Decision::Noul.new(
            instructions: question
          )
        }

        result = @provider.evaluate(state: subject, decisions: decisions)
        ThresholdVerdict.new(result, threshold)
      end

      # Verdict from threshold evaluation.
      class ThresholdVerdict
        attr_reader :result, :threshold

        def initialize(result, threshold)
          @result = result
          @threshold = threshold
        end

        # The raw noul value (0–1, where 1 = strong yes).
        def noul
          answer = @result["verdict"]
          answer&.noul || 0.0
        end

        # Did the subject pass the threshold?
        def passed?
          noul >= @threshold
        end

        # Confidence: distance from 0.5 (0 = uncertain, 0.5 = certain).
        def confidence
          (noul - 0.5).abs
        end

        def to_s
          status = passed? ? "PASS" : "FAIL"
          "#{status} (noul: #{('%.2f' % noul)}, confidence: #{('%.2f' % confidence)})"
        end
      end
    end
  end
end
