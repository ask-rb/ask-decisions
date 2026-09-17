# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::TypesafeTest < Minitest::Test
  API_RESPONSE = {
    "model" => "jev-latest",
    "answers" => {
      "route" => {
        "type" => "choice",
        "choice" => "technical",
        "probabilities" => { "billing" => 0.1, "technical" => 0.8, "sales" => 0.1 },
        "confidence" => 0.82
      },
      "urgent" => {
        "type" => "noul",
        "noul" => 0.92
      },
      "quality" => {
        "type" => "score",
        "score" => 1.6,
        "legend" => { "0" => "Calm", "1" => "Frustrated", "2" => "Very angry" },
        "probabilities" => { "0" => 0.05, "1" => 0.3, "2" => 0.65 },
        "confidence" => 0.78
      }
    },
    "usage" => { "input_tokens" => 312, "output_tokens" => 48 }
  }.freeze

  def setup
    @provider = Ask::Decisions::Typesafe.new(api_key: "test-key")
    stub_request(:post, "https://api.typesafe.ai/v1/systemone")
      .to_return(
        status: 200,
        body: API_RESPONSE.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def test_evaluate_choice
    q = Ask::Decision::Choice.new(
      instructions: "Which team?",
      criteria: { billing: "Payments", technical: "Bugs", sales: "Pricing" }
    )
    result = @provider.evaluate(state: "test", decisions: { "route" => q })

    assert_equal "technical", result["route"].choice
    assert_in_delta 0.82, result["route"].confidence, 0.001
  end

  def test_evaluate_noul
    q = Ask::Decision::Noul.new(instructions: "Is it urgent?")
    result = @provider.evaluate(state: "test", decisions: { "urgent" => q })

    assert_in_delta 0.92, result["urgent"].noul, 0.001
  end

  def test_evaluate_score
    q = Ask::Decision::Score.new(
      instructions: "Rate it",
      criteria: ["Calm", "Frustrated", "Very angry"]
    )
    result = @provider.evaluate(state: "test", decisions: { "quality" => q })

    assert_in_delta 1.6, result["quality"].score, 0.001
    assert_in_delta 0.78, result["quality"].confidence, 0.001
  end

  def test_multiple_decisions_in_one_call
    result = @provider.evaluate(
      state: "test",
      decisions: {
        "route" => Ask::Decision::Choice.new(instructions: "q1", criteria: { billing: "", technical: "", sales: "" }),
        "urgent" => Ask::Decision::Noul.new(instructions: "q2"),
        "quality" => Ask::Decision::Score.new(instructions: "q3", criteria: ["a", "b", "c"])
      }
    )

    assert_equal 3, result.answers.size
    assert result["route"].choice
    assert result["urgent"].noul
    assert result["quality"].score
  end

  def test_usage
    q = Ask::Decision::Noul.new(instructions: "q")
    result = @provider.evaluate(state: "test", decisions: { "q" => q })

    assert_equal 312, result.usage["input_tokens"]
  end

  def test_model
    q = Ask::Decision::Noul.new(instructions: "q")
    result = @provider.evaluate(state: "test", decisions: { "q" => q })

    assert_equal "jev-latest", result.model
  end

  def test_unauthorized
    stub_request(:post, "https://api.typesafe.ai/v1/systemone")
      .to_return(status: 401, body: '{"error":{"message":"bad key"}}')

    q = Ask::Decision::Noul.new(instructions: "q")
    assert_raises(Ask::Unauthorized) do
      @provider.evaluate(state: "test", decisions: { "q" => q })
    end
  end

  def test_rate_limit
    stub_request(:post, "https://api.typesafe.ai/v1/systemone")
      .to_return(status: 429, body: '{"error":{"message":"rate limited"}}')

    q = Ask::Decision::Noul.new(instructions: "q")
    assert_raises(Ask::RateLimitError) do
      @provider.evaluate(state: "test", decisions: { "q" => q })
    end
  end

  def test_sends_auth_header
    q = Ask::Decision::Noul.new(instructions: "q")
    @provider.evaluate(state: "test", decisions: { "q" => q })

    assert_requested(:post, "https://api.typesafe.ai/v1/systemone") do |req|
      req.headers["Authorization"] == "Bearer test-key"
    end
  end

  def test_custom_api_base
    provider = Ask::Decisions::Typesafe.new(api_key: "key", api_base: "https://proxy.example.com")
    stub_request(:post, "https://proxy.example.com/v1/systemone")
      .to_return(status: 200, body: API_RESPONSE.to_json)

    q = Ask::Decision::Noul.new(instructions: "q")
    provider.evaluate(state: "test", decisions: { "q" => q })

    assert_requested(:post, "https://proxy.example.com/v1/systemone")
  end
end
