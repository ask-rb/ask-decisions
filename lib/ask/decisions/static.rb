# frozen_string_literal: true

module Ask
  module Decisions
    # A provider that returns canned answers. For tests and offline fixtures.
    #
    #   Ask::Decisions.configure do |c|
    #     c.default_provider = :static
    #   end
    #
    #   # Or per-call:
    #   Ask::Decisions.decide(
    #     state: "...",
    #     decisions: { "route" => Ask::Decision::Choice.new(instructions: "...", criteria: {...}) },
    #     provider: :static
    #   )
    #
    class Static < Ask::DecisionProvider
      attr_reader :answers

      def initialize(answers: {})
        super()
        @answers = answers.transform_keys(&:to_s).freeze
      end

      # @param state [String, Hash, Array] ignored
      # @param decisions [Hash{String => Decision::Choice|Decision::Score|Decision::Noul}]
      #   used to produce placeholder answers for any missing fixtures
      # @return [DecisionResult::Batch]
      def evaluate(state:, decisions:, model: nil)
        answers = decisions.each_with_object({}) do |(id, decision), h|
          h[id.to_s] = @answers[id.to_s] || default_answer(id, decision)
        end

        Ask::DecisionResult::Batch.new(answers: answers, model: "static")
      end

      private

      def default_answer(id, decision)
        case decision
        when Decision::Choice
          key = decision.criteria.keys.first
          Ask::DecisionResult::ChoiceAnswer.new(
            id: id,
            choice: key,
            probabilities: Hash[decision.criteria.keys.map { |k| [k, 1.0 / decision.criteria.size] }],
            confidence: 1.0
          )
        when Decision::Score
          Ask::DecisionResult::ScoreAnswer.new(
            id: id,
            score: (decision.criteria.size / 2.0),
            legend: Hash[decision.criteria.each_with_index.map { |c, i| [i.to_s, c] }],
            probabilities: Hash[decision.criteria.each_with_index.map { |_, i| [i.to_s, 1.0 / decision.criteria.size] }],
            confidence: 1.0
          )
        when Decision::Noul
          Ask::DecisionResult::NoulAnswer.new(id: id, noul: 0.5)
        else
          raise ArgumentError, "Unknown decision type: #{decision.class}"
        end
      end
    end
  end
end
