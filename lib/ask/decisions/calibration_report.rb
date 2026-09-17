# frozen_string_literal: true

module Ask
  module Decisions
    # Records decision outcomes and produces a calibration report —
    # reliability curves per decision id, variance across runs, and
    # threshold sweep.
    #
    # This is the measurement loop that makes confidence thresholds
    # trustworthy. Without it, thresholds are guesses.
    #
    #   report = Ask::Decisions::CalibrationReport.new
    #
    #   # Record a decision and its outcome.
    #   report.record(
    #     decision_id: "tool.route",
    #     confidence: 0.89,
    #     predicted: "bash",
    #     outcome: "bash",  # what actually happened
    #     latency: 0.12
    #   )
    #
    #   # Generate the report.
    #   summary = report.summarize
    #   summary.accuracy        # => 0.92
    #   summary.calibration     # => 0.85 (Brier-like score)
    #   summary.by_confidence   # => [{ range: "0.9–1.0", count: 15, accuracy: 0.93 }, ...]
    #
    class CalibrationReport
      attr_reader :records

      def initialize
        @records = []
      end

      # Record a decision and its outcome.
      #
      # @param decision_id [String] the decision id
      # @param confidence [Float] the model's confidence
      # @param predicted [String] what the model chose
      # @param outcome [String] what actually happened (ground truth)
      # @param latency [Float, nil] response time in seconds
      # @param metadata [Hash] extra data (tool name, risk level, etc.)
      def record(decision_id:, confidence:, predicted:, outcome:, latency: nil, metadata: {})
        @records << {
          decision_id: decision_id.to_s,
          confidence: confidence.to_f,
          predicted: predicted.to_s,
          outcome: outcome.to_s,
          latency: latency,
          metadata: metadata,
          timestamp: Time.now.to_f
        }
      end

      # Generate the calibration summary.
      #
      # @return [Summary]
      def summarize
        Summary.new(@records)
      end

      # Reset all records.
      def clear
        @records.clear
      end

      # Summary of recorded decisions.
      class Summary
        attr_reader :total, :correct, :accuracy, :calibration, :by_confidence, :by_decision_id

        def initialize(records)
          @records = records
          @total = records.size
          @correct = records.count { |r| r[:predicted] == r[:outcome] }
          @accuracy = @total > 0 ? @correct.to_f / @total : 0.0
          @calibration = compute_calibration(records)
          @by_confidence = bucket_by_confidence(records)
          @by_decision_id = group_by_decision_id(records)
        end

        # Overall accuracy.
        def accuracy_pct
          ("%.1f%%" % (@accuracy * 100))
        end

        # Average latency.
        def avg_latency
          latencies = @records.filter_map { |r| r[:latency] }
          return nil if latencies.empty?
          latencies.sum / latencies.size
        end

        # Print a human-readable report.
        def to_s
          lines = []
          lines << "=== Calibration Report ==="
          lines << "Total decisions: #{@total}"
          lines << "Correct: #{@correct} (#{accuracy_pct})"
          lines << "Calibration (Brier): #{('%.4f' % @calibration)}" if @calibration
          lines << "Avg latency: #{('%.0fms' % (avg_latency * 1000))}" if avg_latency
          lines << ""
          lines << "By confidence band:"
          @by_confidence.each do |band|
            lines << "  #{band[:range]}: #{band[:count]} decisions, #{band[:accuracy_pct]} accuracy"
          end
          lines << ""
          lines << "By decision id:"
          @by_decision_id.each do |id, data|
            lines << "  #{id}: #{data[:count]} decisions, #{data[:accuracy_pct]} accuracy"
          end
          lines.join("\n")
        end

        private

        # Brier-like calibration score: mean squared error between
        # confidence and outcome (1 if correct, 0 if wrong).
        def compute_calibration(records)
          return nil if records.empty?
          records.sum do |r|
            actual = r[:predicted] == r[:outcome] ? 1.0 : 0.0
            (r[:confidence] - actual) ** 2
          end / records.size
        end

        # Bucket records by confidence ranges.
        def bucket_by_confidence(records)
          ranges = [
            { min: 0.9, max: 1.0, label: "0.9–1.0" },
            { min: 0.7, max: 0.9, label: "0.7–0.9" },
            { min: 0.5, max: 0.7, label: "0.5–0.7" },
            { min: 0.3, max: 0.5, label: "0.3–0.5" },
            { min: 0.0, max: 0.3, label: "0.0–0.3" }
          ]

          ranges.filter_map do |range|
            bucket = records.select { |r| r[:confidence] >= range[:min] && r[:confidence] < range[:max] }
            next if bucket.empty?
            correct = bucket.count { |r| r[:predicted] == r[:outcome] }
            acc = correct.to_f / bucket.size
            {
              range: range[:label],
              count: bucket.size,
              accuracy: acc,
              accuracy_pct: "%.1f%%" % (acc * 100),
              avg_confidence: bucket.sum { |r| r[:confidence] } / bucket.size
            }
          end
        end

        # Group records by decision id.
        def group_by_decision_id(records)
          records.group_by { |r| r[:decision_id] }.transform_values do |group|
            correct = group.count { |r| r[:predicted] == r[:outcome] }
            acc = correct.to_f / group.size
            {
              count: group.size,
              accuracy: acc,
              accuracy_pct: "%.1f%%" % (acc * 100),
              avg_confidence: group.sum { |r| r[:confidence] } / group.size
            }
          end
        end
      end
    end
  end
end
