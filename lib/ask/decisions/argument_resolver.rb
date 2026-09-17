# frozen_string_literal: true

module Ask
  module Decisions
    # Resolves tool arguments by asking Jev to fill enum/bool params from the
    # user's turn, while routing free-text params to the generator.
    #
    # This is the hybrid: Jev decides closed-set args, the LLM writes free-text.
    #
    #   resolver = Ask::Decisions::ArgumentResolver.new(provider)
    #   result = resolver.resolve(
    #     tool_name: "linear.create_issue",
    #     params_schema: tool.params_schema,
    #     user_turn: "create a bug in the eng team about login failures",
    #     model: "jev-latest"
    #   )
    #   result.resolved_args   # => {"team" => "eng", "priority" => "high"}
    #   result.needs_generation # => ["title", "description"]
    #   result.confidence      # => 0.85
    #
    class ArgumentResolver
      # @param provider [Ask::DecisionProvider]
      def initialize(provider)
        @provider = provider
      end

      # Resolve as many arguments as possible via Jev decisions.
      #
      # @param tool_name [String] the tool's name (for context in instructions)
      # @param params_schema [Hash] the tool's JSON Schema
      # @param user_turn [String] the user's message
      # @param model [String, nil] model override
      # @return [Resolution]
      def resolve(tool_name:, params_schema:, user_turn:, model: nil)
        properties = params_schema["properties"] || {}
        required = Array(params_schema["required"] || [])

        resolved = {}
        needs_generation = []
        questions = {}

        properties.each do |param_name, prop_schema|
          enum = prop_schema["enum"]
          type = prop_schema["type"]
          desc = prop_schema["description"] || param_name

          if enum && !enum.empty?
            # Closed set → Choice question
            criteria = {}
            enum.each { |v| criteria[v.to_s] = "#{v}" }
            questions[param_name] = Ask::Decision::Choice.new(
              instructions: "What value should the `#{param_name}` parameter be for #{tool_name}?",
              criteria: criteria
            )
          elsif type == "boolean"
            # Boolean → Noul
            questions[param_name] = Ask::Decision::Noul.new(
              instructions: "Should the `#{param_name}` parameter be true?"
            )
          else
            # Free text → generator
            needs_generation << param_name
          end
        end

        if questions.empty?
          return Resolution.new(
            resolved: {},
            needs_generation: required + (properties.keys - required),
            confidence: nil,
            result: nil
          )
        end

        result = @provider.evaluate(
          state: { tool_name: tool_name, user_turn: user_turn },
          decisions: questions,
          model: model
        )

        # Extract resolved values from answers.
        questions.each_key do |param_name|
          answer = result[param_name]
          next unless answer

          case answer
          when DecisionResult::ChoiceAnswer
            resolved[param_name] = answer.choice
          when DecisionResult::NoulAnswer
            resolved[param_name] = answer.yes?
          end
        end

        Resolution.new(
          resolved: resolved,
          needs_generation: needs_generation,
          confidence: result.min_confidence,
          result: result
        )
      end

      # Resolution result.
      class Resolution
        attr_reader :resolved, :needs_generation, :confidence, :result

        def initialize(resolved:, needs_generation:, confidence:, result:)
          @resolved = resolved
          @needs_generation = needs_generation
          @confidence = confidence
          @result = result
        end

        # All args that can be filled right now (resolved + defaults for
        # unmentioned optional params).
        def auto_fill_args
          resolved.dup
        end

        # Whether the LLM needs to generate any arguments.
        def needs_generation? = !needs_generation.empty?

        def confident?(threshold = 0.7)
          return false if confidence.nil?
          confidence >= threshold
        end

        def to_s
          parts = []
          resolved.each { |k, v| parts << "#{k}=#{v.inspect}" }
          parts << "generate: #{needs_generation.join(', ')}" if needs_generation.any?
          parts.join(", ")
        end
      end
    end
  end
end
