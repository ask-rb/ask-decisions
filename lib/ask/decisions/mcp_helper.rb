# frozen_string_literal: true

module Ask
  module Decisions
    # Helper for adding the decide tool to an MCP server.
    #
    #   require "ask-decisions/mcp_helper"
    #
    #   # In your MCP server setup:
    #   tools = [Ask::Decisions::MCPHelper.tool, ...other_tools...]
    #   server = Ask::MCP::Adapters::ToolServer.new(tools)
    #
    module MCPHelper
      # Returns an Ask::Tools::Decide instance configured with the
      # current decision provider. This is the tool to pass to
      # Ask::MCP::Adapters::ToolServer.
      def self.tool
        require "ask/tools/decide"
        Ask::Tools::Decide.new
      end
    end
  end
end
