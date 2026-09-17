# frozen_string_literal: true

require "ask"  # ask-core: Ask::Decision, Ask::DecisionResult, Ask::DecisionProvider
require "json"
require "net/http"
require "uri"

require_relative "ask/decisions/version"
require_relative "ask/decisions/typesafe"
require_relative "ask/decisions/batcher"
require_relative "ask/decisions/cache"
require_relative "ask/decisions/static"
require_relative "ask/decisions/lint"
require_relative "ask/decisions/gate"
require_relative "ask/decisions/output_judge"

# Register built-in providers.
Ask::DecisionProvider.register(:typesafe, Ask::Decisions::Typesafe)
Ask::DecisionProvider.register(:static,   Ask::Decisions::Static)

module Ask
  # Global convenience for making decisions.
  #
  #   Ask.decide(state: "...", decisions: { "route" => Ask::Decision::Choice.new(...) })
  #
  # The provider is resolved from +Ask::Decisions.configuration.default_provider+
  # unless overridden per-call.
  def self.decide(state:, decisions:, provider: nil, model: nil, &block)
    Ask::Decisions.decide(state: state, decisions: decisions, provider: provider, model: model, &block)
  end
end

module Ask
  module Decisions
    class << self
      # Configuration block.
      #
      #   Ask::Decisions.configure do |c|
      #     c.default_provider = :typesafe
      #     c.api_key = ENV["TYPESAFE_API_KEY"]
      #   end
      def configure
        yield configuration
        configuration
      end

      def configuration
        @configuration ||= Configuration.new
      end

      def reset_configuration!
        @configuration = Configuration.new
      end

      # Make a decision call using the configured provider.
      #
      #   Ask::Decisions.decide(
      #     state: { ticket: "..." },
      #     decisions: { "route" => Ask::Decision::Choice.new(instructions: "...", criteria: {...}) }
      #   )
      #
      def decide(state:, decisions:, provider: nil, model: nil)
        provider_name = provider || configuration.default_provider
        resolved = resolve_provider(provider_name)

        # If a block is given, yield a Batcher so the caller can batch questions.
        if block_given?
          batcher = Batcher.new(resolved, state: state, model: model || configuration.default_model)
          yield batcher
          return batcher.execute
        end

        resolved.evaluate(
          state: state,
          decisions: decisions,
          model: model || configuration.default_model
        )
      end

      # Shorthand for batched decisions. Yields a Batcher.
      #
      #   result = Ask::Decisions.batch(state: "...") do |b|
      #     b.ask("route", Ask::Decision::Choice.new(...))
      #     b.ask("urgent", Ask::Decision::Noul.new(...))
      #   end
      def batch(state:, provider: nil, model: nil, &block)
        decide(state: state, decisions: {}, provider: provider, model: model, &block)
      end

      # Resolve a provider by name, raising on unknown.
      def resolve_provider(name)
        klass = Ask::DecisionProvider.resolve(name)

        if configuration.provider_options.any?
          klass.new(**configuration.provider_options)
        else
          klass.new
        end
      end
    end

    # Global configuration for the Decisions module.
    class Configuration
      # @return [Symbol] the default provider name (:typesafe)
      attr_accessor :default_provider

      # @return [String, nil] the default model name ("jev-latest")
      attr_accessor :default_model

      # @return [String, nil] API key (falls back to Ask::Auth or env var)
      attr_accessor :api_key

      # @return [String, nil] base URL override (for proxies / Vercel AI Gateway)
      attr_accessor :api_base

      # @return [Hash] extra options passed to the provider constructor
      attr_accessor :provider_options

      # @return [Float, nil] default timeout in seconds
      attr_accessor :timeout

      def initialize
        @default_provider = :typesafe
        @default_model = "jev-latest"
        @api_key = nil
        @api_base = nil
        @provider_options = {}
        @timeout = 5.0
      end
    end
  end
end
