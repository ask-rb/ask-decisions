# frozen_string_literal: true

require "json"

module Ask
  module Tools
    # A tool that delegates a judgment to a decision model (e.g. Jev).
    # This is the bridge for LLM-driven agents: instead of guessing which
    # tool to call, the agent asks Decide and gets typed answers with
    # calibrated probabilities.
    #
    # The agent sees this as one more tool alongside bash, read, etc.:
    #
    #   decide(state: "...", questions: '{
    #     "route": {
    #       "type": "choice",
    #       "instructions": "Which tool should handle this?",
    #       "criteria": {
    #         "bash": "Run a shell command",
    #         "read": "Read a file",
    #         "none": "Answer directly without tools"
    #       }
    #     }
    #   }')
    #
    class Decide < Ask::Tool
      description "Delegate a judgment to a decision model. Returns typed answers " \
                   "with calibrated probabilities. Use this when you need to classify, " \
                   "route, score, or judge something — instead of guessing, ask the " \
                   "decision model. One call can ask many questions at once."

      param :state, type: :string, desc: "The content to evaluate (JSON string or plain text)", required: true
      param :questions, type: :string, desc: "Questions as JSON: {\"id\": {\"type\": \"choice|score|noul\", \"instructions\": \"...\", \"criteria\": {...}}}", required: true

      def execute(state:, questions:)
        parsed_state = parse_json_safe(state)
        parsed_questions = parse_json_safe(questions)

        unless parsed_questions.is_a?(Hash)
          return Ask::Result.failure("questions must be a JSON object mapping id → question")
        end

        decisions = build_decisions(parsed_questions)
        if decisions.empty?
          return Ask::Result.failure("no valid questions found in the input")
        end

        provider = resolve_provider
        result = provider.evaluate(state: parsed_state, decisions: decisions)

        # Format answers for the LLM — the agent needs to read this.
        output = format_answers(result)
        Ask::Result.success(output)
      rescue JSON::ParserError => e
        Ask::Result.failure("invalid JSON: #{e.message}")
      rescue => e
        Ask::Result.failure("decide failed: #{e.message}")
      end

      private

      # Parse JSON, but return the original string if it's not JSON.
      def parse_json_safe(str)
        return str if str.is_a?(Hash) || str.is_a?(Array)
        JSON.parse(str)
      rescue JSON::ParserError
        str
      end

      # Convert the raw JSON question map into Ask::Decision objects.
      def build_decisions(parsed)
        parsed.each_with_object({}) do |(id, q), h|
          q = q.is_a?(Hash) ? q : {}
          type = q["type"]&.downcase
          instructions = q["instructions"]
          next unless type && instructions

          case type
          when "choice"
            criteria = q["criteria"] || {}
            h[id] = Ask::Decision::Choice.new(instructions: instructions, criteria: criteria)
          when "score"
            criteria = Array(q["criteria"])
            h[id] = Ask::Decision::Score.new(instructions: instructions, criteria: criteria)
          when "noul"
            criteria = q["criteria"] # optional
            opts = { instructions: instructions }
            opts[:criteria] = criteria if criteria
            h[id] = Ask::Decision::Noul.new(**opts)
          end
        end
      end

      # Resolve the decision provider from configuration.
      def resolve_provider
        provider_name = Ask::Decisions.configuration.default_provider
        Ask::Decisions.resolve_provider(provider_name)
      end

      # Format the result batch as a readable JSON string for the LLM.
      def format_answers(result)
        output = { model: result.model, answers: {} }
        result.each do |answer|
          case answer
          when Ask::DecisionResult::ChoiceAnswer
            output[:answers][answer.id] = {
              type: "choice",
              choice: answer.choice,
              probabilities: answer.probabilities,
              confidence: answer.confidence
            }
          when Ask::DecisionResult::ScoreAnswer
            output[:answers][answer.id] = {
              type: "score",
              score: answer.score,
              confidence: answer.confidence,
              legend: answer.legend
            }
          when Ask::DecisionResult::NoulAnswer
            output[:answers][answer.id] = {
              type: "noul",
              noul: answer.noul
            }
          end
        end
        JSON.generate(output)
      end
    end
  end
end
