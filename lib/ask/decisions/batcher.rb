# frozen_string_literal: true

module Ask
  module Decisions
    # Accumulates questions and executes them in a single API call.
    #
    # Jev evaluates all questions in one request in parallel, and adding questions
    # barely changes latency or cost. This batching discipline is the core
    # ergonomic of the decision layer — send every question the turn might need
    # in one call, let Ruby ignore the answers it doesn't reach.
    #
    #   result = Ask::Decisions.batch(state: "...") do |b|
    #     b.ask("route",   Ask::Decision::Choice.new(...))
    #     b.ask("urgent",  Ask::Decision::Noul.new(...))
    #     b.ask("quality", Ask::Decision::Score.new(...))
    #   end
    #   result["route"].choice
    #
    class Batcher
      attr_reader :provider, :state, :model, :questions

      def initialize(provider, state:, model: nil)
        @provider = provider
        @state = state
        @model = model
        @questions = {}
      end

      # Add a question to the batch.
      #
      # @param id [String] the question id (used to access the answer)
      # @param decision [Ask::Decision::Choice, Ask::Decision::Score, Ask::Decision::Noul]
      # @return [self]
      def ask(id, decision)
        @questions[id.to_s] = decision
        self
      end

      # Execute all accumulated questions in a single API call.
      #
      # @return [Ask::DecisionResult::Batch]
      def execute
        return empty_result if @questions.empty?

        @provider.evaluate(
          state: @state,
          decisions: @questions,
          model: @model
        )
      end

      private

      def empty_result
        Ask::DecisionResult::Batch.new(answers: {})
      end
    end
  end
end
