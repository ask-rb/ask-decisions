# frozen_string_literal: true

module Ask
  module Decisions
    # Decision-based tool call repair — replaces the LLM repair pass
    # with a Choice over valid tool names and enum values. This is a
    # real type check, not a prompt-and-hope.
    #
    #   repairer = Ask::Decisions::ToolRepairer.new(provider)
    #   result = repairer.repair(
    #     attempted_tool: "bsh",  # typo
    #     attempted_args: { command: "ls" },
    #     available_tools: [
    #       { name: "bash", description: "Run a shell command" },
    #       { name: "read", description: "Read a file" }
    #     ]
    #   )
    #   result.repaired_tool   # => "bash"
    #   result.repaired?       # => true
    #
    class ToolRepairer
      # @param provider [Ask::DecisionProvider]
      def initialize(provider)
        @provider = provider
      end

      # Attempt to repair a malformed tool call.
      #
      # @param attempted_tool [String] the tool name the LLM tried to use
      # @param attempted_args [Hash] the arguments it passed
      # @param available_tools [Array<Hash>] the valid tool roster
      # @return [RepairResult]
      def repair(attempted_tool:, attempted_args:, available_tools:)
        tool_names = available_tools.map { |t| t[:name] || t["name"] }

        # If the tool name is valid, try to repair args only.
        if tool_names.include?(attempted_tool)
          return repair_args(
            tool_name: attempted_tool,
            args: attempted_args,
            tools: available_tools
          )
        end

        # Tool name is invalid — ask Jev to pick the right one.
        question = Ask::Decision::Choice.new(
          instructions: "The assistant tried to call a tool named '#{attempted_tool}' which does not exist. " \
                        "Which available tool is closest to what the assistant intended?",
          criteria: tool_names.each_with_object({}) { |n, h|
            desc = available_tools.find { |t| (t[:name] || t["name"]) == n }
            h[n] = desc ? (desc[:description] || desc["description"] || n) : n
          }
        )

        result = @provider.evaluate(
          state: { attempted_tool: attempted_tool, attempted_args: attempted_args },
          decisions: { "corrected_tool" => question }
        )

        corrected = result["corrected_tool"]&.choice
        RepairResult.new(
          repaired_tool: corrected || attempted_tool,
          repaired_args: attempted_args,
          repaired: corrected && corrected != attempted_tool,
          confidence: result["corrected_tool"]&.confidence
        )
      end

      private

      def repair_args(tool_name:, args:, tools:)
        tool_def = tools.find { |t| (t[:name] || t["name"]) == tool_name }
        schema = tool_def&.dig(:params_schema) || tool_def&.dig("params_schema") || {}

        resolver = ArgumentResolver.new(@provider)
        resolution = resolver.resolve(
          tool_name: tool_name,
          params_schema: schema,
          user_turn: args.to_json
        )

        merged = resolution.auto_fill_args.merge(args)
        RepairResult.new(
          repaired_tool: tool_name,
          repaired_args: merged,
          repaired: resolution.needs_generation?,
          confidence: resolution.confidence
        )
      end

      # Result of tool call repair.
      class RepairResult
        attr_reader :repaired_tool, :repaired_args, :confidence

        def initialize(repaired_tool:, repaired_args:, repaired:, confidence: nil)
          @repaired_tool = repaired_tool
          @repaired_args = repaired_args
          @repaired = repaired
          @confidence = confidence
        end

        def repaired? = @repaired

        def to_s
          if repaired?
            "repaired: #{repaired_tool}(#{repaired_args.keys.join(', ')})"
          else
            "unrepairable"
          end
        end
      end
    end
  end
end
