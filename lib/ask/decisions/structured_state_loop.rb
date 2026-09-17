# frozen_string_literal: true

module Ask
  module Decisions
    # A structured-state computer-use loop: extract state from a screen
    # (OCR or DOM), ask Jev to pick the next action, execute it, repeat.
    #
    # This is the ask-computer integration. Instead of a vision-LLM loop
    # (expensive, slow), we use OCR/DOM → Jev → action at ~$0.0002/step.
    #
    #   loop = Ask::Decisions::StructuredStateLoop.new(provider)
    #   result = loop.run(
    #     goal: "open Safari and search for Ruby gems",
    #     state_fn: -> { extract_screen_state() },  # returns Hash
    #     action_fn: ->(action) { execute_action(action) },  # returns void
    #     max_steps: 20
    #   )
    #   result.completed?  # => true
    #   result.steps       # => 8
    #
    class StructuredStateLoop
      ACTIONS = {
        click: "Click on an element identified by its position or label",
        type: "Type text into the focused input field",
        scroll: "Scroll the page or window in a direction",
        key: "Press a keyboard key or combination",
        wait: "Wait for the screen to update",
        done: "The goal has been achieved"
      }.freeze

      # @param provider [Ask::DecisionProvider]
      def initialize(provider)
        @provider = provider
      end

      # Run the decision loop until the goal is achieved or max steps hit.
      #
      # @param goal [String] what the user wants to accomplish
      # @param state_fn [Proc] returns a Hash representing the current screen state
      # @param action_fn [Proc] executes an action Hash, returns void
      # @param max_steps [Integer] safety limit
      # @return [LoopResult]
      def run(goal:, state_fn:, action_fn:, max_steps: 20)
        history = []
        max_steps.times do |step|
          state = state_fn.call
          decision = decide_next(goal: goal, state: state, history: history)

          if decision.done?
            return LoopResult.new(completed: true, steps: step + 1, history: history)
          end

          action = decision.action
          action_fn.call(action)
          history << { step: step, state_summary: summarize_state(state), action: action }
        end

        LoopResult.new(completed: false, steps: max_steps, history: history)
      end

      private

      def decide_next(goal:, state:, history:)
        recent = history.last(5).map { |h| "#{h[:action][:type]}: #{h[:action][:target]}" }
        state_text = summarize_state(state)

        questions = {
          action_type: Ask::Decision::Choice.new(
            instructions: "What is the next action to achieve the goal?",
            criteria: ACTIONS.transform_keys(&:to_s)
          ),
          target: Ask::Decision::Noul.new(
            instructions: "Is the goal already achieved based on the current state?"
          )
        }

        result = @provider.evaluate(
          state: {
            goal: goal,
            current_state: state_text,
            recent_actions: recent,
            step: history.size
          },
          decisions: questions
        )

        action_type = result["action_type"]&.choice&.to_sym || :wait
        goal_met = result["target"]&.noul&.>= 0.8

        StepDecision.new(
          action_type: action_type,
          goal_met: goal_met,
          confidence: result["action_type"]&.confidence
        )
      end

      def summarize_state(state)
        return state.to_s if state.is_a?(String)
        state.map { |k, v| "#{k}: #{v}" }.join("\n")
      end

      # A single step decision.
      class StepDecision
        attr_reader :action_type, :confidence

        def initialize(action_type:, goal_met:, confidence: nil)
          @action_type = action_type
          @goal_met = goal_met
          @confidence = confidence
        end

        def done? = @goal_met

        def action
          { type: @action_type, target: nil }
        end
      end

      # Result of the loop.
      class LoopResult
        attr_reader :steps, :history

        def initialize(completed:, steps:, history:)
          @completed = completed
          @steps = steps
          @history = history
        end

        def completed? = @completed

        def to_s
          @completed ? "completed in #{steps} steps" : "not completed after #{steps} steps"
        end
      end
    end
  end
end
