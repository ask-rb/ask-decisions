# frozen_string_literal: true

module Ask
  module Decisions
    # Gates actions on confidence thresholds. Extends the existing
    # approval system with a confidence axis: high confidence → act,
    # medium → require approval, low → escalate to LLM/human.
    #
    #   policy = Ask::Decisions::ConfidencePolicy.new
    #   policy.add_rule(:bash, risk: :low, act_threshold: 0.5, review_threshold: 0.3)
    #   policy.add_rule(:write, risk: :high, act_threshold: 0.9, review_threshold: 0.7)
    #
    #   decision = policy.evaluate(tool: "bash", confidence: 0.6)
    #   decision.action  # => :act
    #
    #   decision = policy.evaluate(tool: "write", confidence: 0.8)
    #   decision.action  # => :review (need approval)
    #
    class ConfidencePolicy
      # Default rules by risk level. Matches the pi-jev calibration:
      # read-only tools act at 0.5, destructive tools need 0.9.
      DEFAULT_RULES = {
        low:    { act_threshold: 0.5, review_threshold: 0.3 },
        medium: { act_threshold: 0.7, review_threshold: 0.5 },
        high:   { act_threshold: 0.9, review_threshold: 0.7 }
      }.freeze

      def initialize
        @rules = {}        # tool_name → { risk:, act_threshold:, review_threshold: }
        @default_risk = :medium
      end

      # Add a rule for a specific tool.
      #
      # @param tool [String, Symbol] the tool name
      # @param risk [Symbol] :low, :medium, or :high
      # @param act_threshold [Float, nil] override the act threshold
      # @param review_threshold [Float, nil] override the review threshold
      def add_rule(tool, risk: :medium, act_threshold: nil, review_threshold: nil)
        defaults = DEFAULT_RULES[risk] || DEFAULT_RULES[:medium]
        @rules[tool.to_s] = {
          risk: risk,
          act_threshold: act_threshold || defaults[:act_threshold],
          review_threshold: review_threshold || defaults[:review_threshold]
        }
      end

      # Set the default risk level for tools without explicit rules.
      def default_risk=(risk)
        @default_risk = risk
      end

      # Evaluate whether an action should proceed based on confidence.
      #
      # @param tool [String] the tool name
      # @param confidence [Float, nil] the decision's confidence
      # @return [PolicyDecision]
      def evaluate(tool:, confidence: nil)
        rule = @rules[tool.to_s] || DEFAULT_RULES[@default_risk] || DEFAULT_RULES[:medium]

        action = classify(confidence, rule)
        PolicyDecision.new(
          tool: tool,
          confidence: confidence,
          action: action,
          risk: rule[:risk],
          act_threshold: rule[:act_threshold],
          review_threshold: rule[:review_threshold]
        )
      end

      private

      def classify(confidence, rule)
        return :escalate if confidence.nil?

        if confidence >= rule[:act_threshold]
          :act
        elsif confidence >= rule[:review_threshold]
          :review
        else
          :escalate
        end
      end

      # Decision from policy evaluation.
      class PolicyDecision
        attr_reader :tool, :confidence, :action, :risk, :act_threshold, :review_threshold

        def initialize(tool:, confidence:, action:, risk:, act_threshold:, review_threshold:)
          @tool = tool
          @confidence = confidence
          @action = action
          @risk = risk
          @act_threshold = act_threshold
          @review_threshold = review_threshold
        end

        def act?       = action == :act
        def review?    = action == :review
        def escalate?  = action == :escalate

        def to_s
          case action
          when :act      then "act on #{tool} (confidence #{fmt})"
          when :review   then "review #{tool} (confidence #{fmt}, need approval)"
          when :escalate then "escalate #{tool} (confidence #{fmt}, below threshold)"
          end
        end

        private

        def fmt
          confidence ? "%.2f" % confidence : "nil"
        end
      end
    end
  end
end
