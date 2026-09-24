# frozen_string_literal: true

require "json"

module Ask
  module Decisions
    # Tool-call arguments arrive as a Hash in some runtimes and as their JSON
    # wire representation in others. Decision prompts need one stable shape.
    module ToolArguments
      def self.normalize(arguments)
        return arguments if arguments.is_a?(Hash)

        parsed = JSON.parse(arguments) if arguments.is_a?(String)
        return parsed if parsed.is_a?(Hash)

        {"_raw_arguments" => arguments}
      rescue JSON::ParserError
        {"_raw_arguments" => arguments}
      end
    end
  end
end
