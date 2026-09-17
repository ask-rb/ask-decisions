# frozen_string_literal: true

begin
  require "ask-auth"
rescue LoadError
  # ask-auth is optional — only needed for automatic credential resolution.
end

module Ask
  module Decisions
    # HTTP client for the TypeSafe / System One API.
    #
    #   provider = Ask::Decisions::Typesafe.new
    #   result = provider.evaluate(
    #     state: "Help! My payouts are failing.",
    #     decisions: {
    #       "is_urgent" => Ask::Decision::Noul.new(instructions: "Does this convey urgency?"),
    #       "route"     => Ask::Decision::Choice.new(
    #         instructions: "Which team should handle this?",
    #         criteria: { "billing" => "Payments", "technical" => "Bugs" }
    #       )
    #     }
    #   )
    #   result["is_urgent"].noul      # => 0.92
    #   result["route"].choice        # => "technical"
    #   result["route"].confidence   # => 0.82
    #
    # The API key is resolved in order:
    # 1. +api_key+ passed to the constructor
    # 2. +Ask::Decisions.configuration.api_key+
    # 3. +Ask::Auth.resolve(:typesafe_api_key)+
    # 4. +ENV["TYPESAFE_API_KEY"]+
    #
    class Typesafe < Ask::DecisionProvider
      API_BASE = "https://api.typesafe.ai"
      API_PATH = "/v1/systemone"

      RETRYABLE_STATUSES = [429, 529].freeze

      attr_reader :api_key, :api_base, :model, :timeout

      def initialize(api_key: nil, api_base: nil, model: nil, timeout: nil, **_opts)
        super()
        @api_key = api_key || resolve_api_key
        @api_base = (api_base || Ask::Decisions.configuration.api_base || API_BASE).chomp("/")
        @model = model || Ask::Decisions.configuration.default_model || "jev-latest"
        @timeout = timeout || Ask::Decisions.configuration.timeout || 5.0
      end

      # @return [DecisionResult::Batch]
      def evaluate(state:, decisions:, model: nil)
        model_name = model || @model
        payload = build_payload(state, decisions, model_name)
        response = post(payload)
        parse_response(response, decisions.keys)
      end

      private

      # --- Request building ---

      def build_payload(state, decisions, model_name)
        questions = decisions.transform_values(&:to_h)
        {
          state: state,
          model: model_name,
          questions: questions
        }
      end

      def post(payload)
        uri = URI.parse("#{@api_base}#{API_PATH}")
        body = JSON.generate(payload)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        request = Net::HTTP::Post.new(uri.path)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request["User-Agent"] = "ask-decisions/#{Ask::Decisions::VERSION}"
        request.body = body

        response = http.request(request)
        handle_response(response)
      end

      def handle_response(response)
        status = response.code.to_i
        body = response.body

        case status
        when 200..299
          JSON.parse(body)
        when 401, 403
          raise Ask::Unauthorized, "TypeSafe: #{status} #{extract_message(body)}"
        when 429
          retry_after = response["retry-after"]&.to_f
          raise Ask::RateLimitError.new(
            "TypeSafe: rate limited",
            retry_after: retry_after
          )
        when 422
          raise Ask::ProviderError.new("TypeSafe: #{extract_message(body)}", status_code: status)
        when 500
          raise Ask::ServerError, "TypeSafe: server error #{extract_message(body)}"
        when 529
          retry_after = response["retry-after"]&.to_f
          raise Ask::RateLimitError.new(
            "TypeSafe: overloaded",
            retry_after: retry_after
          )
        else
          raise Ask::ProviderError.new(
            "TypeSafe: HTTP #{status} #{extract_message(body)}",
            status_code: status
          )
        end
      end

      # --- Response parsing ---

      def parse_response(parsed, question_ids)
        answers = {}
        question_ids.each do |id|
          raw = parsed.dig("answers", id)
          next unless raw

          answers[id] = parse_answer(id, raw)
        end

        Ask::DecisionResult::Batch.new(
          answers: answers,
          model: parsed["model"],
          usage: parsed["usage"],
          latency: nil # set by caller if timing
        )
      end

      def parse_answer(id, raw)
        case raw["type"]
        when "choice"
          Ask::DecisionResult::ChoiceAnswer.new(
            id: id,
            choice: raw["choice"],
            probabilities: raw["probabilities"] || {},
            confidence: raw["confidence"]&.to_f
          )
        when "score"
          Ask::DecisionResult::ScoreAnswer.new(
            id: id,
            score: raw["score"]&.to_f,
            legend: raw["legend"] || {},
            probabilities: raw["probabilities"] || {},
            confidence: raw["confidence"]&.to_f
          )
        when "noul"
          Ask::DecisionResult::NoulAnswer.new(
            id: id,
            noul: raw["noul"]&.to_f
          )
        else
          raise Ask::ProviderError, "TypeSafe: unknown answer type #{raw["type"].inspect} for #{id}"
        end
      end

      # --- Helpers ---

      def resolve_api_key
        Ask::Decisions.configuration.api_key ||
          (defined?(Ask::Auth) && begin
            Ask::Auth.resolve(:typesafe_api_key)
          rescue Ask::Auth::MissingCredential
            nil
          end) ||
          ENV["TYPESAFE_API_KEY"]
      end

      def extract_message(body)
        parsed = JSON.parse(body)
        parsed["error"]["message"] || parsed["error"] || body
      rescue JSON::ParserError
        body
      end
    end
  end
end
