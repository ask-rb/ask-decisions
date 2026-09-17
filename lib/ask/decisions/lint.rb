# frozen_string_literal: true

module Ask
  module Decisions
    # Lints decision definitions before they hit the API. Warns on patterns
    # known to reduce Jev's accuracy (from TypeSafe's jaggedness page and
    # measured failures in pi-jev).
    #
    # Run in dev/test as a rake task or at definition time:
    #
    #   warnings = Ask::Decisions::Lint.check(decisions)
    #   warnings.each { |w| puts "WARNING: #{w}" }
    #
    module Lint
      module_function

      # Lint a hash of decisions.
      #
      # @param decisions [Hash{String => Ask::Decision::Choice|Score|Noul}]
      # @return [Array<String>] warnings (empty if clean)
      def check(decisions)
        warnings = []
        decisions.each do |id, decision|
          warnings.concat(check_one(id, decision))
        end
        warnings
      end

      # @private
      def check_one(id, decision)
        w = []
        instructions = decision.respond_to?(:instructions) ? decision.instructions : ""

        # Reasoning paths in instructions — measured to cause failures
        # ("cannot be recovered from version control" → 0.77 on destructive instead of 0.99).
        if instructions.match?(/\b(because|since|unless|therefore|still recoverable|cannot be recovered|which means|this implies)\b/i)
          w << "#{id}: instructions contain a reasoning path or justification clause. " \
               "Ask the plain property instead — measured to reduce accuracy."
        end

        # Math/arithmetic
        if instructions.match?(/\b(how many|count|total|sum|average|multiply|add up|how much)\b/i)
          w << "#{id}: instructions ask for counting or arithmetic. " \
               "Jev is unreliable at math — compute in Ruby."
        end

        # Date comparison
        if instructions.match?(/\b(earlier|later|which date|which comes first|how many days between|what day)\b/i)
          w << "#{id}: instructions ask for date comparison. " \
               "Extract components as Choices and compare in Ruby."
        end

        # Large cardinality without warning
        if decision.respond_to?(:criteria) && decision.criteria.is_a?(Hash) && decision.criteria.size > 255
          w << "#{id}: #{decision.criteria.size} options exceeds Jev's cardinality limit of 255. " \
               "Use a two-stage rank → shortlist → rerank."
        end

        # Score with fewer than 2 levels
        if decision.is_a?(Decision::Score) && decision.criteria.size < 2
          w << "#{id}: Score needs at least 2 criteria levels (got #{decision.criteria.size})."
        end

        # Missing none/other on Choice (soft warning)
        if decision.is_a?(Decision::Choice) &&
           !decision.criteria.keys.any? { |k| k.to_s.downcase.match?(/\b(none|other|none of the above|unknown)\b/) }
          w << "#{id}: Choice without a none/other option. " \
               "Consider adding one so the model can reject all options."
        end

        w
      end
    end
  end
end
