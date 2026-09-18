# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::CalibrationReportTest < Minitest::Test
  def test_records_and_summarizes
    report = Ask::Decisions::CalibrationReport.new
    report.record(decision_id: "route", confidence: 0.9, predicted: "bash", outcome: "bash")
    report.record(decision_id: "route", confidence: 0.8, predicted: "read", outcome: "bash")
    report.record(decision_id: "urgent", confidence: 0.95, predicted: "yes", outcome: "yes")

    summary = report.summarize
    assert_equal 3, summary.total
    assert_equal 2, summary.correct
    assert summary.accuracy > 0.6
  end

  def test_by_confidence_buckets
    report = Ask::Decisions::CalibrationReport.new
    5.times { report.record(decision_id: "q", confidence: 0.95, predicted: "a", outcome: "a") }
    3.times { report.record(decision_id: "q", confidence: 0.6, predicted: "b", outcome: "c") }

    summary = report.summarize
    assert summary.by_confidence.any? { |b| b[:range] == "0.9–1.0" }
    assert summary.by_confidence.any? { |b| b[:range] == "0.5–0.7" }
  end

  # The surest answer there is has to be in the report: a confidence of exactly
  # 1.0 fell out of every band while the upper bound was exclusive.
  def test_a_certain_decision_lands_in_the_top_band
    report = Ask::Decisions::CalibrationReport.new
    report.record(decision_id: "q", confidence: 1.0, predicted: "a", outcome: "a")

    top = report.summarize.by_confidence.find { |b| b[:range] == "0.9–1.0" }

    assert_equal 1, top[:count]
    assert_equal 1.0, top[:avg_confidence]
  end

  def test_by_decision_id
    report = Ask::Decisions::CalibrationReport.new
    report.record(decision_id: "route", confidence: 0.9, predicted: "a", outcome: "a")
    report.record(decision_id: "urgent", confidence: 0.8, predicted: "yes", outcome: "no")

    summary = report.summarize
    assert summary.by_decision_id.key?("route")
    assert summary.by_decision_id.key?("urgent")
  end

  def test_calibration_brier_score
    report = Ask::Decisions::CalibrationReport.new
    # Perfect: confidence matches outcome exactly
    report.record(decision_id: "q", confidence: 1.0, predicted: "a", outcome: "a")
    report.record(decision_id: "q", confidence: 0.0, predicted: "b", outcome: "c")

    summary = report.summarize
    assert_in_delta 0.0, summary.calibration, 0.001
  end

  def test_empty_report
    report = Ask::Decisions::CalibrationReport.new
    summary = report.summarize
    assert_equal 0, summary.total
    assert_equal 0.0, summary.accuracy
  end

  def test_clear
    report = Ask::Decisions::CalibrationReport.new
    report.record(decision_id: "q", confidence: 0.9, predicted: "a", outcome: "a")
    report.clear
    assert_equal 0, report.records.size
  end

  def test_to_s
    report = Ask::Decisions::CalibrationReport.new
    report.record(decision_id: "route", confidence: 0.9, predicted: "bash", outcome: "bash")
    summary = report.summarize
    assert summary.to_s.include?("Calibration Report")
    assert summary.to_s.include?("1 decisions")
  end
end
