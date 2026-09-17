# frozen_string_literal: true

module Ask
  module Decisions
    # Caches DecisionProvider results keyed on (state, questions).
    # Jev is self-consistent — identical inputs return identical outputs —
    # so a cache is safe and prevents redundant calls when the same decision
    # is made multiple times in a turn (e.g. guard + rerun).
    #
    #   cached = Ask::Decisions::Cache.new(provider, ttl: 120)
    #   cached.evaluate(state: s, decisions: qs)  # hits the API
    #   cached.evaluate(state: s, decisions: qs)  # returns the cached result
    #
    class Cache
      attr_reader :provider, :ttl

      def initialize(provider, ttl: 120)
        @provider = provider
        @ttl = ttl
        @store = {}
      end

      def evaluate(state:, decisions:, model: nil)
        key = cache_key(state, decisions, model)
        entry = @store[key]

        if entry && !expired?(entry)
          return entry[:result]
        end

        result = @provider.evaluate(state: state, decisions: decisions, model: model)
        @store[key] = { result: result, timestamp: Time.now.to_f }
        result
      end

      def clear
        @store.clear
        nil
      end

      def size
        @store.size
      end

      private

      def cache_key(state, decisions, model)
        digest = ::JSON.generate({
          state: state,
          decisions: decisions.transform_values(&:to_h),
          model: model
        })
        [state_hash(digest), model].join(":")
      end

      def state_hash(data)
        # Use a simple digest for cache keys — not cryptographic, just dedup.
        require "digest" unless defined?(::Digest)
        Digest::MD5.hexdigest(data)
      end

      def expired?(entry)
        (Time.now.to_f - entry[:timestamp]) > @ttl
      end
    end
  end
end
