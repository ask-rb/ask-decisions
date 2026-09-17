# frozen_string_literal: true

module Ask
  module Decisions
    # One request, several answers, about one piece of state.
    #
    # The questions in a decision call are independent and run in parallel, so
    # asking three costs no more latency than asking one. That makes "ask
    # everything this call might need" the right instinct rather than a false
    # economy — and makes this the shared shape for doing it: a Choice over a
    # described set of options, with anything else the caller needs riding
    # along in the same request.
    #
    # The caller owns *what* to ask — which options, in what words. This owns
    # asking it once and handing back the answers.
    #
    #   reader = Ask::Decisions::Reader.new(
    #     provider,
    #     id: "lane",
    #     instructions: "Which of these best describes what the person wants?",
    #     options: {"knowledge" => "Asks about the business", "booking" => "Wants to book"},
    #     also: {"urgent" => Ask::Decision::Noul.new(instructions: "Is this urgent?")}
    #   )
    #   batch = reader.read(state: {message: "What time do you close?"})
    #   reader.choice(batch).choice      # => "knowledge"
    #   batch["urgent"].noul             # => 0.12
    #
    class Reader
      # How much of an option's description to keep. A description is the
      # separator between one option and the others, and a long one buries the
      # part that separates. What is dropped is said out loud, because a
      # silently clipped option reads as a whole one.
      DEFAULT_LIMIT = 160

      # The number of characters the elision marker itself needs.
      ELISION_ROOM = 20

      attr_reader :id, :instructions, :options

      # @param provider [Ask::DecisionProvider]
      # @param id [String, Symbol] the question id the Choice is asked under.
      #   Ids are for the caller's code and are never sent to the model.
      # @param instructions [String] the question the options answer
      # @param options [Hash{String => String}] option => what belongs in it
      # @param also [Hash{String => Decision::Choice,Decision::Score,Decision::Noul}]
      #   further questions asked in the same request
      # @param limit [Integer] characters kept per option description
      def initialize(provider, id:, instructions:, options:, also: {}, limit: DEFAULT_LIMIT)
        @provider = provider
        @id = id.to_s
        @instructions = instructions
        @options = options
        @also = also
        @limit = limit

        if @also.key?(@id)
          raise ArgumentError, "#{@id.inspect} is asked twice: once as the choice, once in also"
        end
      end

      # Ask everything about +state+ in one request.
      #
      # @param state [String, Hash, Array] the whole context, sent once
      # @param model [String, nil] model override
      # @return [Ask::DecisionResult::Batch]
      def read(state:, model: nil)
        @provider.evaluate(state: state, decisions: questions, model: model)
      end

      # The Choice answer, or nil when nothing came back for it.
      def choice(batch) = batch[@id]

      private

      def questions
        {id => choice_question}.merge(@also)
      end

      def choice_question
        Ask::Decision::Choice.new(instructions: instructions, criteria: described_options)
      end

      def described_options
        options.transform_values { |description| truncate(description) }
      end

      def truncate(value)
        text = value.to_s
        return text if text.length <= @limit

        "#{text[0, @limit - ELISION_ROOM]}…[#{text.length - @limit + ELISION_ROOM} chars elided]"
      end
    end
  end
end
