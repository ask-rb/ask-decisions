# ask-decisions

Use the `decide` tool when you need to classify, route, score, or judge something.
Instead of guessing or generating text to reason about a choice, delegate to the
decision model and get typed answers with calibrated probabilities.

## When to use decide

Use it when the answer is a **closed set** — one of N options, a score on a spectrum,
or a yes/no judgment. Don't use it when you need to generate text, code, or prose.

Good:
- "Which tool should handle this request?" (choice)
- "Is this code change safe to merge?" (noul)
- "How urgent is this ticket?" (score)
- "Which agent should I delegate to?" (choice)
- "Does this output contain a secret?" (noul)

Bad:
- "Write me a summary" → use generation
- "Fix this code" → use tools
- "What's the weather?" → use tools

## How to call it

Call the `decide` tool with `state` and `questions`.

### Choice — pick one option

```
decide(
  state: "The customer wrote: I was charged twice for order A-104. Please refund.",
  questions: '{
    "route": {
      "type": "choice",
      "instructions": "Which team should handle this?",
      "criteria": {
        "billing": "Payment or subscription issues",
        "technical": "Bugs, outages, or integration failures",
        "sales": "Pricing or account questions"
      }
    }
  }'
)
```

### Noul — yes/no judgment

```
decide(
  state: "Help! My payouts have been failing for 3 days.",
  questions: '{
    "urgent": {
      "type": "noul",
      "instructions": "Does this message convey urgency or time-sensitivity?"
    }
  }'
)
```

### Score — rate on a spectrum

```
decide(
  state: "The code passes all tests but has no error handling for edge cases.",
  questions: '{
    "quality": {
      "type": "score",
      "instructions": "How thorough is this code change?",
      "criteria": ["Superficial", "Adequate", "Thorough", "Excellent"]
    }
  }'
)
```

### Many questions in one call

All questions run in parallel against the same state. This is cheap — add every
question you might need:

```
decide(
  state: "...",
  questions: '{
    "route": { "type": "choice", "instructions": "...", "criteria": {...} },
    "urgent": { "type": "noul", "instructions": "..." },
    "quality": { "type": "score", "instructions": "...", "criteria": ["low", "high"] }
  }'
)
```

## Reading the answer

The response is a JSON object with an `answers` map:

- **Choice**: `choice` (the selected option), `probabilities` (distribution), `confidence` (0–1)
- **Noul**: `noul` (0–1, where 1 = strong yes, 0 = strong no)
- **Score**: `score` (weighted position), `confidence` (0–1), `legend` (level descriptions)

## Confidence and escalation

Every answer comes with a confidence value (or for Noul, a strength value). Use it:

- **High confidence** → act on the answer directly
- **Medium confidence** → proceed with caution or ask for confirmation
- **Low confidence** → escalate to the user, ask for clarification, or fall back to reasoning

For Noul, "confidence" is the distance from 0.5: `|noul - 0.5|`. A noul of 0.96
has strength 0.46 (strong yes). A noul of 0.51 has strength 0.01 (uncertain).

## Tips

- Write the **instructions** as a clear, specific question — the model answers the
  question you wrote, not the one you meant
- Keep questions **atomic** — one judgment per question. If a decision depends on
  multiple factors, ask each factor separately and combine in your reasoning
- Add a `none` / `other` option to Choice questions so the model can reject all options
  rather than guessing
- **Don't** ask for counting, arithmetic, or date comparisons — those belong in code

## Integration pattern (Rails)

The standard integration follows a three-layer architecture: **decide** → **act** → **fallback**.

### 1. Configure in an initializer

```ruby
# config/initializers/ask_decisions.rb
Rails.application.config.after_initialize do
  key = begin
    Ask::Auth.resolve([:typesafe, :api_key], :typesafe_api_key)
  rescue Ask::Auth::MissingCredential
    nil
  end

  Ask::Decisions.configure do |config|
    config.default_provider = :typesafe
    config.default_model = ENV.fetch("TYPESAFE_MODEL", "jev-latest")
    config.api_key = key
    config.timeout = ENV.fetch("TYPESAFE_TIMEOUT", "2.5").to_f
  end
end
```

### 2. Build a fail-open decisions module

```ruby
module Decisions
  class << self
    def available?
      Ask::Decisions.configuration.api_key.present?
    end

    def evaluate_review(findings:, criteria:, task_context: "")
      return nil unless available?

      judge = Ask::Decisions::QualityJudge.new(provider)
      verdict = judge.evaluate(
        request: criteria.to_json,
        response: findings.to_json,
        rubric: { correctness: "...", security: "..." },
        threshold: 2.5
      )
      verdict.accepted? ? :accept : :revise
    rescue => e
      Rails.logger.warn("Decisions.evaluate_review failed: #{e.message}")
      nil
    end

    private

    def provider
      Ask::Decisions.resolve_provider(Ask::Decisions.configuration.default_provider)
    end
  end
end
```

### 3. Integrate with fallback

```ruby
def evaluate_criteria(findings, criteria)
  # Try Jev first
  jev = Decisions.evaluate_review(findings: findings, criteria: criteria)
  return jev == :accept if jev

  # Mechanical fallback
  case criteria["auto_approve_if"]
  when "no_critical" then findings.none? { |f| f["severity"] == "critical" }
  when "no_findings" then findings.empty?
  else findings.empty?
  end
end
```

### Key properties

- **Fail-open**: no key, timeout, or error → returns nil → fallback runs
- **One call, many questions**: batch all decisions in a single request (~100ms)
- **Compact state**: small JSON hash, never raw transcripts
- **Confidence thresholds**: code owns the pass/review/block boundaries
