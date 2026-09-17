# frozen_string_literal: true

module Ask
  module Decisions
    # Runs a set of test cases against a decision provider and produces
    # a calibration report. Used to measure whether Jev's confidence is
    # trustworthy on YOUR decisions.
    #
    #   harness = Ask::Decisions::CalibrationHarness.new(provider)
    #
    #   harness.add_case(
    #     id: "urgent_message",
    #     state: "Help! My server is down!",
    #     decisions: { "urgent" => Ask::Decision::Noul.new(instructions: "Is this urgent?") },
    #     expected: { "urgent" => { noul_above: 0.7 } }
    #   )
    #
    #   report = harness.run
    #   puts report
    #
    class CalibrationHarness
      def initialize(provider)
        @provider = provider
        @cases = []
      end

      # Add a test case.
      #
      # @param id [String] a descriptive id for this case
      # @param state [String, Hash] the state to evaluate
      # @param decisions [Hash] the questions to ask
      # @param expected [Hash] expected outcomes for assertions:
      #   - { choice_is: "value" } — check choice answer
      #   - { noul_above: 0.7 } — check noul is above threshold
      #   - { noul_below: 0.3 } — check noul is below threshold
      #   - { score_above: 2.0 } — check score is above threshold
      #   - { confidence_above: 0.7 } — check confidence
      # @param runs [Integer] how many times to run this case (for variance)
      def add_case(id:, state:, decisions:, expected: {}, runs: 1)
        @cases << { id: id, state: state, decisions: decisions, expected: expected, runs: runs }
      end

      # Run all test cases and produce a calibration report.
      #
      # @return [CalibrationReport::Summary]
      def run
        report = CalibrationReport.new

        @cases.each do |tc|
          tc[:runs].times do |run_idx|
            result = @provider.evaluate(
              state: tc[:state],
              decisions: tc[:decisions]
            )

            tc[:decisions].each do |decision_id, decision|
              answer = result[decision_id.to_s]
              next unless answer

              predicted, confidence = extract_prediction(answer)
              outcome = check_expected(tc[:expected][decision_id], answer)
              correct = predicted == outcome

              report.record(
                decision_id: "#{tc[:id]}.#{decision_id}",
                confidence: confidence || 0.5,
                predicted: predicted.to_s,
                outcome: outcome.to_s,
                metadata: { run: run_idx, case_id: tc[:id] }
              )
            end
          end
        end

        report.summarize
      end

      private

      def extract_prediction(answer)
        case answer
        when DecisionResult::ChoiceAnswer
          [answer.choice, answer.confidence]
        when DecisionResult::ScoreAnswer
          [answer.score, answer.confidence]
        when DecisionResult::NoulAnswer
          [answer.noul, nil]  # noul has no confidence
        else
          [nil, nil]
        end
      end

      def check_expected(expected, answer)
        return "pass" unless expected

        if expected[:choice_is]
          answer.respond_to?(:choice) && answer.choice == expected[:choice_is] ? "pass" : "fail"
        elsif expected[:noul_above]
          answer.respond_to?(:noul) && answer.noul >= expected[:noul_above] ? "pass" : "fail"
        elsif expected[:noul_below]
          answer.respond_to?(:noul) && answer.noul <= expected[:noul_below] ? "pass" : "fail"
        elsif expected[:score_above]
          answer.respond_to?(:score) && answer.score >= expected[:score_above] ? "pass" : "fail"
        elsif expected[:confidence_above]
          answer.respond_to?(:confidence) && answer.confidence && answer.confidence >= expected[:confidence_above] ? "pass" : "fail"
        else
          "pass"
        end
      end
    end
  end
end
