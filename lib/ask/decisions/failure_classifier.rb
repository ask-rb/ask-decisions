# frozen_string_literal: true

module Ask
  module Decisions
    # Classifies tool output into failure categories and provides actionable
    # advice. Wraps the OutputJudge with a retry-oriented interface.
    #
    #   classifier = Ask::Decisions::FailureClassifier.new(provider)
    #   verdict = classifier.classify(
    #     tool: "bash",
    #     output: "npm ERR! code ECONNRESET",
    #     args: { command: "npm test" },
    #     attempt: 1
    #   )
    #   verdict.retryable?     # => true
    #   verdict.advice         # => "Retry unchanged."
    #   verdict.should_retry?  # => true (attempt 1 < max_retries)
    #
    class FailureClassifier
      DEFAULT_MAX_RETRIES = 3

      # @param provider [Ask::DecisionProvider]
      # @param max_retries [Integer] maximum retry attempts before giving up
      # @param output_limit [Integer] max chars of output to send
      def initialize(provider, max_retries: DEFAULT_MAX_RETRIES, output_limit: 2000)
        @judge = OutputJudge.new(provider, output_limit: output_limit)
        @max_retries = max_retries
      end

      # Classify a tool result and produce a retry decision.
      #
      # @param tool [String] the tool name
      # @param output [String] the tool's stdout/stderr
      # @param args [Hash] the original tool arguments
      # @param attempt [Integer] which attempt this is (1-based)
      # @return [ClassifyResult]
      def classify(tool:, output:, args: {}, attempt: 1)
        judge_result = @judge.judge(tool: tool, output: output, args: args)
        ClassifyResult.new(judge_result, attempt, @max_retries)
      end

      # Result of classifying a tool output.
      class ClassifyResult
        attr_reader :judge_result, :attempt, :max_retries

        def initialize(judge_result, attempt, max_retries)
          @judge_result = judge_result
          @attempt = attempt
          @max_retries = max_retries
        end

        def failure_class = judge_result.failure_class
        def advice = judge_result.advice
        def leak? = judge_result.leak?

        # Is this a failure that could succeed on retry?
        def retryable?
          return false if leak?
          return false if failure_class == "no_failure"
          # transient and environment are retryable with backoff
          %w[transient environment].include?(failure_class)
        end

        # Should we actually retry right now? (attempt < max_retries)
        def should_retry?
          retryable? && attempt < max_retries
        end

        # Should we stop retrying and report to the user?
        def give_up?
          !retryable? || attempt >= max_retries
        end

        # Human-readable summary of the classification.
        def to_s
          if leak?
            "LEAK detected in output"
          elsif failure_class == "no_failure"
            "no failure"
          else
            "#{failure_class}: #{advice} (attempt #{attempt}/#{max_retries})"
          end
        end
      end
    end
  end
end
