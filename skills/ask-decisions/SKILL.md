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
