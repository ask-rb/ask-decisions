# ask-decisions

Decision primitives and providers for the [ask-rb](https://github.com/ask-rb) ecosystem. Ask Jev (or any System One model) structured questions — classify, route, score, guard — and get typed answers with calibrated probabilities. LLMs generate text. Deciders decide.

```ruby
result = Ask.decide(
  state: "Help! My payouts have been failing for 3 days.",
  decisions: {
    "route" => Ask::Decision::Choice.new(
      instructions: "Which team should handle this?",
      criteria: { billing: "Payment issues", technical: "Bugs", sales: "Pricing" }
    ),
    "urgent" => Ask::Decision::Noul.new(
      instructions: "Does this message convey urgency?"
    )
  }
)
# result["route"].choice       # => "billing"
# result["route"].confidence  # => 0.89
# result["urgent"].noul       # => 0.96
```

## Installation

```ruby
gem "ask-decisions"
```

## Setup

```ruby
require "ask-decisions"

Ask::Decisions.configure do |c|
  c.default_provider = :typesafe  # or :static for tests
  c.default_model = "jev-latest"
end
```

## The four verbs

Everything Jev does with LLMs falls into one of these patterns:

| Verb | Shape | Example |
|---|---|---|
| **Route** | decide → generate | Jev picks the tool; LLM writes the answer |
| **Filter** | generate → decide | LLM proposes facts; Jev keeps the good ones |
| **Replace** | decide, no generate | Triage, scoring, relevance — no text needed |
| **Guard** | decide ⟶ gate generate | Screen input/output; gate actions on confidence |

Anything expressible as a closed set becomes a decision. Anything that must produce new text stays a generation.

## Core primitives

Three question types, three answer types:

```ruby
# Choice — pick one option from a set
Ask::Decision::Choice.new(
  instructions: "Which team?",
  criteria: { billing: "Payments", technical: "Bugs", none: "None of these" }
)

# Score — rate on a spectrum
Ask::Decision::Score.new(
  instructions: "How urgent?",
  criteria: ["Not urgent", "Somewhat urgent", "Very urgent"]
)

# Noul — yes/no with probability
Ask::Decision::Noul.new(
  instructions: "Does this convey urgency?"
)
```

## Batching

Jev evaluates all questions in one request in parallel. Send every question you might need:

```ruby
result = Ask::Decisions.batch(state: "...") do |b|
  b.ask("route", Ask::Decision::Choice.new(...))
  b.ask("urgent", Ask::Decision::Noul.new(...))
  b.ask("quality", Ask::Decision::Score.new(...))
end
# One API call, three answers.
```

## Confidence

Every choice/score answer carries calibrated confidence. Noul answers carry a value (0–1) with no separate confidence — use the distance from 0.5 as strength.

```ruby
result["route"].confident?(0.7)  # => true
result["urgent"].strength        # => 0.46 (distance from 0.5)
result["urgent"].yes?            # => true (noul >= 0.5)
```

## Swapping providers

The registry makes providers swappable:

```ruby
# Use Jev in production
Ask::Decisions.configure { |c| c.default_provider = :typesafe }

# Use canned answers in tests
Ask::Decisions.configure { |c| c.default_provider = :static }

# Register a future provider
Ask::DecisionProvider.register(:openjev, MyProvider)
Ask::Decisions.configure { |c| c.default_provider = :openjev }
```

## Gate (pre-tool-call)

Calibrated intent judge — 4 questions in one request:

```ruby
gate = Ask::Decisions::Gate.new(provider)
verdict = gate.judge(tool: "bash", args: { command: "rm -rf src" })
verdict.passed?    # => false
verdict.flagged    # => [:destructive, :beyond_scope]
```

## OutputJudge (post-tool-call)

Screens tool output for leaks and classifies failures:

```ruby
judge = Ask::Decisions::OutputJudge.new(provider)
result = judge.judge(tool: "bash", output: "npm ERR! code ECONNRESET")
result.leak?           # => false
result.failure_class   # => "transient"
result.advice          # => "Retry unchanged."
```

## ToolRouter

Routes user turns to the right tool:

```ruby
router = Ask::Decisions::ToolRouter.new(provider, tools: tool_roster)
result = router.route(user_turn: "run the tests")
result.tool         # => "bash"
result.confidence   # => 0.92
```

## ConfidencePolicy

Risk-tiered action gating:

```ruby
policy = Ask::Decisions::ConfidencePolicy.new
policy.add_rule("bash", risk: :low)
policy.add_rule("rm", risk: :high)

policy.evaluate(tool: "bash", confidence: 0.6).action   # => :act
policy.evaluate(tool: "rm", confidence: 0.8).action      # => :review
```

## Calibration

Measure whether confidence is trustworthy on YOUR decisions:

```ruby
harness = Ask::Decisions::CalibrationHarness.new(provider)
harness.add_case(
  id: "urgent_ticket",
  state: "Help! Server down!",
  decisions: { "urgent" => Ask::Decision::Noul.new(instructions: "Is this urgent?") },
  expected: { "urgent" => { noul_above: 0.7 } },
  runs: 10
)
report = harness.run
puts report  # reliability curve per decision id, accuracy by confidence band
```

## Lint

Catch anti-patterns before they hit the API:

```ruby
warnings = Ask::Decisions::Lint.check({
  "good" => Ask::Decision::Noul.new(instructions: "Is this urgent?"),
  "bad" => Ask::Decision::Choice.new(
    instructions: "Which team? Since this cannot be recovered...",
    criteria: { a: "A", b: "B" }
  )
})
# => ["bad: instructions contain a reasoning path...", "bad: Choice without a none/other option..."]
```

## License

MIT
