# frozen_string_literal: true

require "test_helper"

class Ask::Decisions::RerankerTest < Minitest::Test
  PASSAGES = [
    { id: "doc1", text: "To reset your password, go to Settings > Security." },
    { id: "doc2", text: "Our pricing plans start at $9/month." },
    { id: "doc3", text: "Password reset instructions are in the FAQ." }
  ].freeze

  def setup
    @provider = Ask::Decisions::Static.new
    @reranker = Ask::Decisions::Reranker.new(@provider)
  end

  def test_returns_all_passages
    ranked = @reranker.rerank(query: "how to reset password", passages: PASSAGES)
    assert_equal 3, ranked.size
  end

  def test_sorted_by_score
    ranked = @reranker.rerank(query: "how to reset password", passages: PASSAGES)
    scores = ranked.map { |p| p[:score] }
    assert_equal scores, scores.sort.reverse
  end

  def test_each_has_id_and_score
    ranked = @reranker.rerank(query: "q", passages: PASSAGES)
    ranked.each do |p|
      assert p[:id]
      assert p.key?(:score)
      assert p.key?(:confidence)
    end
  end

  def test_empty_passages
    ranked = @reranker.rerank(query: "q", passages: [])
    assert_equal [], ranked
  end

  def test_preserves_text
    ranked = @reranker.rerank(query: "q", passages: PASSAGES)
    texts = ranked.map { |p| p[:text] }
    PASSAGES.each { |p| assert_includes texts, p[:text] }
  end
end
