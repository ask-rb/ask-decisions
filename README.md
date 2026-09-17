# ask-decisions

Typed decision primitives for the [ask-rb](https://github.com/ask-rb) ecosystem. Ask Jev (or any System One model) structured questions and get typed answers with calibrated probabilities — no text generation, no hallucination, no type errors.

```ruby
Ask.decide(
  state: "Help! My payouts are failing for 3 days.",
  decisions: {
    "route" => Ask::Decision::Choice.new(
      instructions: "Which team should handle this?",
      criteria: { billing: "Payments", technical: "Bugs", sales: "Pricing" }
    ),
    "urgent" => Ask::Decision::Noul.new(
      instructions: "Does this message convey urgency?"
    )
  }
)
# result["route"].choice       # => "billing"
# result["route"].confidence  # => 0.72
# result["urgent"].noul       # => 0.91
```

## Installation

```ruby
# Gemfile
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

## Swapping providers

The `Ask::DecisionProvider` registry lets you swap implementations behind the same interface:

```ruby
# Use Jev in production
Ask::Decisions.configure { |c| c.default_provider = :typesafe }

# Use canned answers in tests
Ask::Decisions.configure { |c| c.default_provider = :static }

# Register a future provider
Ask::DecisionProvider.register(:openjev, MyOpenJevProvider)
Ask::Decisions.configure { |c| c.default_provider = :openjev }
```

## License

MIT
