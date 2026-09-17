# frozen_string_literal: true

module Ask
  module Decisions
    # Post-tool-call output judge: screens the result for leaks and classifies
    # failures. Two questions, one request (~126ms median from pi-jev).
    #
    #   judge = Ask::Decisions::OutputJudge.new(provider)
    #   result = judge.judge(
    #     tool: "bash",
    #     output: "npm ERR! code ECONNRESET",
    #     args: { command: "npm test" }
    #   )
    #   result.leak?       # => false
    #   result.failure_class  # => "transient"
    #   result.advice      # => "retry unchanged"
    #
    class OutputJudge
      # Calibrated questions from pi-jev.
      QUESTIONS = {
        leaks_secret: Ask::Decision::Noul.new(
          instructions: "Does this output contain a secret, credential, private key, or access token?"
        ),
        failure_class: Ask::Decision::Choice.new(
          instructions: "What kind of failure is this?",
          criteria: {
            "no_failure" => "The command succeeded or produced normal output",
            "transient" => "A temporary error — network timeout, rate limit, DNS hiccup. Safe to retry unchanged.",
            "environment" => "A missing dependency, wrong version, port in use, or wrong permissions on a file. Fix the environment before retrying.",
            "code_bug" => "A type error, syntax error, assertion failure, or test failure in the code itself. The code must change.",
            "permission" => "Access denied, insufficient privileges. Do not retry without elevated permissions.",
            "user_error" => "Bad invocation, wrong arguments, or incorrect usage by the caller."
          }
        )
      }.freeze

      # Advice table: maps failure class to a one-line instruction.
      # Derived from pi-jev's CLASS_ADVICE — adding a class is a row.
      ADVICE = {
        "no_failure"  => nil,
        "transient"   => "Retry unchanged.",
        "environment" => "Fix the environment before retrying (missing dependency, port conflict, wrong version).",
        "code_bug"    => "The code must change — do not retry the same command.",
        "permission"  => "Do not retry without elevated permissions.",
        "user_error"  => "Fix the invocation arguments."
      }.freeze

      # @param provider [Ask::DecisionProvider]
      # The class that means nothing went wrong. A host's outcome question has
      # to offer it, because the judge runs after every judged call and not
      # only after a suspicious one: without it, every successful call would
      # read as a failure.
      SUCCESS_CLASS = "no_failure"

      # A host judges two things about an output: whether it leaked something
      # (`:leaks_secret`), and what happened (`:failure_class`). Those two ids
      # are the gem's contract and stay fixed; the questions' words, the
      # classes they can answer with, and the advice per class are the host's —
      # a coding agent's failures are code bugs and broken environments, a
      # business's are "we don't offer that" and "the system is down".
      #
      # @param questions [Hash{Symbol => Decision}] what to ask about a result.
      #   Must answer under :leaks_secret and :failure_class, and the outcome
      #   question must offer the class above among its criteria.
      # @param advice [Hash{String => String,nil}] one line per class the
      #   outcome question can answer with. A class with no line is advice the
      #   model does not get.
      # @param tools [Array<String>, nil] tools to judge (nil = the gem's own
      #   default, the coding agent's shell tool — pass the host's own)
      # @param leak_threshold [Float] noul threshold for leak detection
      # @param failure_threshold [Float] confidence threshold for failure classification
      # @param output_limit [Integer] max characters of output to send
      def initialize(provider, questions: QUESTIONS, advice: ADVICE, tools: nil,
        leak_threshold: 0.90, failure_threshold: 0.60, output_limit: 2000)
        @provider = provider
        @questions = judgeable(questions)
        @advice = advice
        @tools = tools || ["bash"]
        @leak_threshold = leak_threshold
        @failure_threshold = failure_threshold
        @output_limit = output_limit
      end

      # Judge a tool result after execution.
      #
      # @param tool [String] the tool name
      # @param output [String] the tool's stdout/stderr
      # @param args [Hash] the original tool arguments
      # @return [OutputResult]
      def judge(tool:, output:, args: {})
        return OutputResult.empty unless @tools.include?(tool)

        truncated = truncate(output, @output_limit)
        state = { output: truncated, tool_arguments: truncate_values(args, 400) }

        result = @provider.evaluate(state: state, decisions: @questions)
        OutputResult.new(result, @leak_threshold, @failure_threshold, advice: @advice)
      end

      private

      # A host's questions have to answer the two things the result reads, and
      # the outcome question has to be able to say that nothing went wrong.
      # Both are silent failures otherwise — a judge that reads nothing judges
      # nothing — so they are refused at construction instead.
      def judgeable(questions)
        missing = %i[leaks_secret failure_class] - questions.keys.map(&:to_sym)
        unless missing.empty?
          raise ArgumentError, "the output judge needs questions for #{missing.inspect}"
        end

        criteria = Array(questions[:failure_class].criteria&.keys)
        unless criteria.include?(SUCCESS_CLASS)
          raise ArgumentError,
            "the failure_class question must offer #{SUCCESS_CLASS.inspect} among its criteria, " \
            "or every successful call reads as a failure"
        end

        questions
      end

      def truncate(str, limit)
        return "" if str.nil?
        str.length > limit ? "#{str[0, limit]}…[#{str.length - limit} chars elided]" : str
      end

      def truncate_values(hash, limit)
        hash.transform_values do |v|
          v.is_a?(String) && v.length > limit ? "#{v[0, limit]}…[#{v.length - limit} chars elided]" : v
        end
      end

      # Typed result from the output judge.
      class OutputResult
        attr_reader :leak_noul, :failure_class, :failure_confidence, :advice

        def initialize(batch, leak_threshold, failure_threshold, advice: ADVICE)
          leak_answer = batch["leaks_secret"]
          failure_answer = batch["failure_class"]

          @leak_noul = leak_answer&.noul || 0.0
          @leak_threshold = leak_threshold

          @failure_class = failure_answer&.choice || SUCCESS_CLASS
          @failure_confidence = failure_answer&.confidence || 0.0
          @failure_threshold = failure_threshold
          @advice = advice[@failure_class]
        end

        def leak?
          @leak_noul >= @leak_threshold
        end

        def failure?
          @failure_class != SUCCESS_CLASS && @failure_confidence >= @failure_threshold
        end

        def to_s
          parts = []
          parts << "LEAK (#{@leak_noul})" if leak?
          parts << "#{@failure_class} (#{'%.2f' % @failure_confidence})" if failure?
          parts.empty? ? "clean" : parts.join(", ")
        end
      end

      # Empty result when tool is not judged.
      def self.empty_result_class
        OutputResult
      end

      class OutputResult
        def self.empty
          new(Ask::DecisionResult::Batch.new(answers: {}), 0.9, 0.6)
        end
      end
    end
  end
end
