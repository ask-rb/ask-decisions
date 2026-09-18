# frozen_string_literal: true

module Ask
  module Decisions
    # Bridges ask-decisions into ask-agent. Configures an agent session
    # to use decision providers for the gate, output judge, evaluator,
    # reflector, failure classification, loop detection, and confidence
    # policy — while leaving the LLM in place for text generation.
    #
    # This is the "seamlessly usable" integration: one config line
    # activates the full decision layer.
    #
    #   Ask::Agent.configure do |c|
    #     c.default_model = "gpt-4o"
    #     c.decision_provider = :typesafe
    #   end
    #
    # Or per-session:
    #
    #   session = Ask::Agent::Session.new(
    #     model: "gpt-4o",
    #     decision_provider: :typesafe
    #   )
    #
    class AgentAdapter
      attr_reader :provider, :gate, :output_judge, :failure_classifier,
                  :loop_detector, :confidence_policy, :quality_judge,
                  :reflection_judge, :tool_repairer

      # @param provider_name [Symbol, String] the decision provider to use
      # @param config [Hash] optional overrides
      def initialize(provider_name, config = {})
        @provider = resolve_provider(provider_name)
        @config = config

        # Build all decision components with the same provider.
        @gate = Gate.new(@provider, **gate_config)
        @output_judge = OutputJudge.new(@provider, **output_judge_config)
        @failure_classifier = FailureClassifier.new(@provider, **failure_classifier_config)
        @loop_detector = LoopDetector.new(@provider)
        @confidence_policy = build_confidence_policy
        @quality_judge = QualityJudge.new(@provider)
        @reflection_judge = ReflectionJudge.new(@provider, **reflection_judge_config)
        @tool_repairer = ToolRepairer.new(@provider)
      end

      # Build a decision-based compactor for the current provider.
      #
      #   compactor = adapter.build_compactor(preserve_recent: 6)
      #   result = compactor.compact(session.messages)
      #   result.messages  # => pruned conversation
      #
      def build_compactor(**opts)
        Ask::Decisions::Compactor.new(@provider, **opts)
      end

      # Generate before_tool hooks for ask-agent.
      # Returns an array of callables that match the Hooks interface.
      def before_tool_hooks
        [build_gate_hook]
      end

      # Generate after_tool hooks for ask-agent.
      def after_tool_hooks
        [build_output_judge_hook]
      end

      # Build a tool-call repair function that uses the ToolRepairer.
      def repair_tool_call(tool_call, available_tools)
        @tool_repairer.repair(
          attempted_tool: tool_call.name,
          attempted_args: tool_call.arguments || {},
          available_tools: available_tools
        )
      end

      # Classify a tool result for retry decisions.
      def classify_failure(tool:, output:, args: {}, attempt: 1)
        @failure_classifier.classify(
          tool: tool, output: output, args: args, attempt: attempt
        )
      end

      # Check for agent loops.
      def check_loop(recent_turns:, current_tool: nil, current_args: nil, turn_count: 0)
        @loop_detector.check(
          recent_turns: recent_turns,
          current_tool: current_tool,
          current_args: current_args,
          turn_count: turn_count
        )
      end

      # Evaluate answer quality.
      def evaluate_quality(request:, response:, rubric: nil)
        opts = { request: request, response: response }
        opts[:rubric] = rubric if rubric
        @quality_judge.evaluate(**opts)
      end

      # Run reflection.
      def reflect(request:, response:, attempt: 1)
        @reflection_judge.reflect(
          request: request, response: response, attempt: attempt
        )
      end

      # Evaluate confidence for an action.
      def evaluate_confidence(tool:, confidence:)
        @confidence_policy.evaluate(tool: tool, confidence: confidence)
      end

      private

      def resolve_provider(name)
        Ask::Decisions.resolve_provider(name)
      end

      # What the host judges, and how high the bar is. The questions are the
      # host's because risk is: a booking tool and a shell tool are not
      # dangerous for the same reason, and a gate written for one says nothing
      # useful about the other.
      def gate_config
        {
          questions: @config[:gate_questions],
          thresholds: @config[:gate_thresholds],
          tools: @config[:gate_tools]
        }.compact
      end

      def output_judge_config
        {
          questions: @config[:output_questions],
          advice: @config[:output_advice],
          tools: @config[:output_tools],
          output_limit: @config[:output_limit]
        }.compact
      end

      def failure_classifier_config
        { max_retries: @config[:max_retries] }.compact
      end

      def reflection_judge_config
        { max_reflections: @config[:max_reflections] }.compact
      end

      def build_confidence_policy
        policy = ConfidencePolicy.new
        @config[:risk_rules]&.each do |tool, risk|
          policy.add_rule(tool, risk: risk)
        end
        policy
      end

      # Build a before_tool hook that runs the Gate.
      def build_gate_hook
        gate = @gate
        lambda do |tool_call, context|
          args = tool_call.respond_to?(:arguments) ? tool_call.arguments : {}
          working_dir = context[:working_dir] || context["working_dir"]
          user_message = context[:user_message] || context["user_message"]

          verdict = gate.judge(
            tool: tool_call.name,
            args: args || {},
            working_dir: working_dir,
            user_message: user_message
          )

          if verdict.flagged?
            { action: :block, reason: verdict.to_s }
          else
            { action: :proceed }
          end
        end
      end

      # Build an after_tool hook that runs the OutputJudge.
      def build_output_judge_hook
        judge = @output_judge
        lambda do |tool_call, result|
          output = result.respond_to?(:output) ? result.output : result.to_s
          args = tool_call.respond_to?(:arguments) ? tool_call.arguments : {}

          output_result = judge.judge(
            tool: tool_call.name,
            output: output.to_s,
            args: args || {}
          )

          if output_result.leak?
            { action: :block, reason: "Secret detected in output" }
          else
            { action: :proceed, failure_class: output_result.failure_class }
          end
        end
      end
    end
  end
end
