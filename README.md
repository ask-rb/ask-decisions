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

## Triage

Read a message once and answer everything a turn needs about it — which lane
it belongs to, how the person sounds, whether they want a human. All in one
request, so the extra questions cost no extra latency:

```ruby
triage = Ask::Decisions::Triage.new(provider, lanes: {
  "knowledge" => "Asks about the business, its services, prices, or hours",
  "booking"   => "Wants to book an appointment or asks what times are free",
  "human"     => "Wants to speak to a person, or describes an emergency",
  "close"     => "Says goodbye or is done",
  "chat"      => "Small talk or a greeting needing no action",
  "unclear"   => "None of these is clear; a clarifying question is needed first"
})

verdict = triage.read(message: "What time do you close on Saturdays?")
verdict.lane        # => "knowledge"
verdict.confidence  # => 1.0
verdict.certain?(0.7)   # => true
verdict.sentiment       # => 1.0 (0 = upset, 1 = neutral, 2 = warm)
verdict.wants_human?    # => false
```

### Lanes, not tools

Route to a **lane**, then let code map the lane to its tools. Measured on a
19-tool roster, same model and same messages:

| Routed to | Correct |
|---|---|
| one of the 19 tools | 10/16 |
| one of 7 lanes | **19/20** |

The tools overlapped — seven of them answered questions about the business,
and which one holds the answer is found by calling them, not by reading the
message. Routing straight to a tool asks for a distinction the message does
not carry. A lane is the part that *is* decidable from the message alone.

A reading should narrow, never grant: let the lane take tools away from a
turn, and let the agent's own definition stay the ceiling.

### Why there is no tool router

There was one — `ToolRouter`, a Choice over a tool roster. It is gone, because
the measurement above is the argument against it: asked to pick one of
nineteen tools the answer was right 10 times in 16, and asked to pick a lane
19 times in 20. Same model, same messages.

The reason is structural, not a tuning problem. Overlapping tools cannot be
separated by a message: which of seven knowledge tools holds the answer is
discovered by *calling* them. Routing to a tool asks a question the message
does not carry, so a router that answers it is guessing with confidence.

What replaces it is the lane plus code:

- the lane withholds the tools the turn cannot need,
- the lane's pre-read fetches what the turn will obviously ask for,
- and the model chooses within the narrow roster, where choosing is a
  decision it can actually make — because it can see the candidates' results.

If you do need a decider to pick a tool, the roster it picks from has to be
small and disjoint — a handful of tools a message can actually distinguish.
If it is not, the fix is a narrower lane or a pre-read, not a better prompt.

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
