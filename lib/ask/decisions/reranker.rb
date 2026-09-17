# frozen_string_literal: true

module Ask
  module Decisions
    # Reranks retrieved passages using Jev. One Score question per
    # query–candidate pair, scored on a relevance rubric.
    #
    # This is the ask-rag integration: replace a cosine floor with a
    # per-passage relevance judgment. TypeSafe's CLERC cookbook reports
    # top-1 accuracy 5% → 18%, top-10 38% → 62%.
    #
    #   reranker = Ask::Decisions::Reranker.new(provider)
    #   ranked = reranker.rerank(
    #     query: "How do I reset my password?",
    #     passages: [
    #       { id: "doc1", text: "To reset your password, go to Settings..." },
    #       { id: "doc2", text: "Our pricing plans start at $9/month..." }
    #     ]
    #   )
    #   ranked.first  # => { id: "doc1", score: 3.8, confidence: 0.9 }
    #
    class Reranker
      # @param provider [Ask::DecisionProvider]
      def initialize(provider)
        @provider = provider
      end

      # Rerank passages by relevance to a query.
      #
      # @param query [String] the search query
      # @param passages [Array<Hash>] each with :id and :text
      # @param model [String, nil] model override
      # @return [Array<Hash>] sorted by score descending, each with :id, :score, :confidence
      def rerank(query:, passages:, model: nil)
        return [] if passages.empty?

        questions = passages.each_with_object({}) do |passage, h|
          id = passage[:id] || passage["id"] || "passage_#{h.size}"
          text = passage[:text] || passage["text"] || ""

          h["rel_#{id}"] = Ask::Decision::Score.new(
            instructions: "How relevant is this passage to answering the query?",
            criteria: [
              "Not relevant — unrelated to the query",
              "Marginally relevant — shares some keywords but doesn't address the query",
              "Relevant — partially answers the query",
              "Highly relevant — directly answers the query"
            ]
          )
        end

        state = { query: query, passages: passages.map { |p|
          { id: p[:id] || p["id"], text: truncate(p[:text] || p["text"] || "", 1000) }
        }}

        result = @provider.evaluate(state: state, decisions: questions, model: model)

        passages.each_with_index.map do |passage, i|
          id = passage[:id] || passage["id"] || "passage_#{i}"
          answer = result["rel_#{id}"]
          {
            id: id,
            text: passage[:text] || passage["text"],
            score: answer&.score || 0.0,
            confidence: answer&.confidence || 0.0
          }
        end.sort_by { |p| -p[:score] }
      end

      private

      def truncate(str, limit)
        return "" if str.nil?
        str.length > limit ? "#{str[0, limit]}…" : str
      end
    end
  end
end
