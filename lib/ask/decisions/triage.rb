# frozen_string_literal: true

module Ask
  module Decisions
    # Reads an incoming message once and answers every question the turn
    # needs about it: which lane it belongs to, how the person sounds, and
    # whether they want a human.
    #
    # Lanes are the coarse intents a message can be sorted into — "a
    # question about the business", "wants to book", "wants a person" — and
    # they are deliberately fewer and coarser than the tools they lead to.
    #
    # That coarseness is the point. Routing a message straight to one of
    # twenty tools asks the model to make a distinction the message does not
    # carry: seven tools may all answer from the same knowledge, and which
    # one holds the answer is discovered by calling them, not by reading the
    # request. Lanes are the part that *is* decidable from the message; code
    # maps the lane to its tools, and a second, narrower decision happens
    # only when one is needed.
    #
    # Ranks measured on a 19-tool roster: tool-level routing 10/16, lane
    # routing 19/20 — same model, same messages.
    #
    #   triage = Ask::Decisions::Triage.new(provider, lanes: {
    #     "knowledge" => "Asks about the business, its services, prices, hours, or policies",
    #     "booking"   => "Wants to book an appointment or asks what times are free",
    #     "human"     => "Wants to speak to a person, or describes an emergency",
    #     "close"     => "Says goodbye or is done",
    #     "chat"      => "Small talk or a greeting needing no action",
    #     "unclear"   => "None of these is clear; a clarifying question is needed first"
    #   })
    #   verdict = triage.read(message: "What time do you close on Saturdays?")
    #   verdict.lane        # => "knowledge"
    #   verdict.confidence  # => 1.0
    #   verdict.certain?(0.7) # => true
    #
    # All questions go in one request: asking more costs no extra latency.
    class Triage
      # The verdict on one message. +lane+ is always one of the lanes the
      # caller supplied, or nil when the call failed.
      class Verdict
        attr_reader :lane, :confidence, :sentiment, :wants_human, :answers

        def initialize(lane:, confidence:, sentiment: nil, wants_human: nil, answers: {})
          @lane = lane
          @confidence = confidence
          @sentiment = sentiment
          @wants_human = wants_human
          @answers = answers
        end

        # A failed or unreadable call produces no verdict: nothing is known,
        # and the caller keeps whatever it would have done without us.
        def known? = !lane.nil?

        # Is the lane above the threshold for acting on it without asking
        # again? Callers pass the one threshold they are willing to be wrong
        # at; there is no universal one.
        def certain?(threshold = 0.7)
          return false unless confidence
          confidence >= threshold
        end

        # Does the person want a person? An unanswered question is not a yes,
        # and neither is a coin flip: 0.5 means the model had no idea, which
        # is the one answer that must not read as consent.
        def wants_human?(threshold = 0.5)
          return false unless wants_human
          wants_human > threshold
        end

        def to_s
          return "no verdict" unless known?
          "#{lane} (#{format('%.2f', confidence || 0)})"
        end
      end

      # The auxiliary questions every triage asks, on top of the lane.
      # They ride along in the same request, so they are free — which is the
      # whole reason to ask for them up front rather than in a second call.
      SENTIMENT = Ask::Decision::Score.new(
        instructions: "How does the person writing sound? Judge their mood, not the topic.",
        criteria: ["Upset or angry", "Neutral", "Warm or pleased"]
      )

      WANTS_HUMAN = Ask::Decision::Noul.new(
        instructions: "Does the person want to speak to a human rather than deal with a bot? " \
                      "Contact details, business hours, and product questions do not count as wanting a human."
      )

      attr_reader :lanes

      # @param provider [Ask::DecisionProvider]
      # @param lanes [Hash] lane name => a sentence describing what belongs in it
      # @param instructions [String] the question the lanes answer
      # @param context_limit [Integer] how much context to carry into state
      def initialize(provider, lanes:, instructions: nil, context_limit: 600)
        @provider = provider
        @lanes = lanes
        @instructions = instructions || default_instructions
        @context_limit = context_limit
      end

      # Read a message and return a Verdict.
      #
      # @param message [String] the message to read
      # @param context [String, nil] a short description of who is writing to whom
      # @param model [String, nil] model override
      # @return [Verdict]
      def read(message:, context: nil, model: nil)
        result = @provider.evaluate(state: build_state(message, context), decisions: questions, model: model)
        lane = result["lane"]
        sentiment = result["sentiment"]
        human = result["wants_human"]

        Verdict.new(
          lane: lane&.choice,
          confidence: lane&.confidence,
          sentiment: sentiment&.score,
          wants_human: human&.noul,
          answers: { "lane" => lane, "sentiment" => sentiment, "wants_human" => human }
        )
      end

      private

      def questions
        {
          "lane" => Ask::Decision::Choice.new(instructions: @instructions, criteria: @lanes),
          "sentiment" => SENTIMENT,
          "wants_human" => WANTS_HUMAN
        }
      end

      # The state is the message and a line of context. Longer state has
      # been measured to make Jev worse, not better — everything irrelevant
      # is a chance to misread what is relevant.
      def build_state(message, context)
        state = { message: truncate(message, 2000) }
        state[:context] = truncate(context, @context_limit) if context && !context.to_s.empty?
        state
      end

      def default_instructions
        "Which of these best describes what the person writing wants? " \
          "Choose by what they are asking for, not by how they phrase it."
      end

      def truncate(value, limit)
        text = value.to_s
        return text if text.length <= limit
        "#{text[0, limit - 20]}…[#{text.length - limit + 20} chars elided]"
      end
    end
  end
end
