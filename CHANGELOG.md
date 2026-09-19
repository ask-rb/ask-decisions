# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.6] - 2026-09-19

### Fixed

- **The output judge hook no longer crashes the first tool call of every
  turn.** ask-agent hands after-tool hooks three arguments — the tool
  call, the result, and the turn context — and the hook took two, raising
  `ArgumentError` inside `run_after_tool` before any tool could answer.
  A session rescued it into the generic "sorry" reply, so every chat turn
  that reached for a tool returned nothing. The hook now accepts the
  context it is given, and the hook test calls it the way ask-agent does.

## [0.2.5] - 2026-09-18

### Fixed

- **Dropping one of several tool calls no longer orphans its siblings.**
  When an assistant message carried multiple tool calls and Jev dropped
  one, the Compactor removed the whole message — including the calls Jev
  said to keep, stranding their results without a call. A drop now removes
  the dropped call from its message; the message survives when it still
  has text or surviving calls, and disappears only when the drop empties it.
- **A drop touching a pinned message keeps the compactor's promises.** A
  result is never left without its call, and a pinned message is never
  removed — a drop against either now downgrades to keeping the pair
  (truncating the result when only the call is pinned), and the stats say
  what actually happened: fully pinned pairs report `pinned` instead of
  counting as evaluated work.

## [0.2.4] - 2026-09-18

### Fixed

- **`resolve_provider` memoizes the provider instance.** Every call to
  `resolve_provider` previously created a new `Typesafe` (or other provider)
  object. In a pipeline with 10+ decision calls per cycle, this meant 10+
  redundant allocations with identical configuration. The provider is now
  cached for the lifetime of the process — it holds only read-only state
  (API key, base URL, model, timeout) set once at boot.

## [0.2.3] - 2026-09-18

### Added

- **`Ask::Decisions::ThresholdJudge`** — binary accept/reject judge for
  simple gate decisions. Runs a single Noul question and thresholds the
  result. Use this when you need "does this pass?" without the full
  rubric of `QualityJudge`. Returns a `ThresholdVerdict` with `passed?`,
  `noul`, and `confidence`.

## [0.2.2] - 2026-09-18

### Fixed

- **A confidence of exactly 1.0 lands in the top band of
  `CalibrationReport#summarize`.** The bands were half-open at both ends
  (`min <= confidence < max`), so the surest answer a decider can give — 1.0,
  and in practice the most common one — belonged to no band at all. A report
  written for setting a threshold was quietly dropping the decisions that most
  justify one. The top band is now inclusive of 1.0.

## [0.2.1] - 2026-09-17

### Added

- **The host owns the judgement: `Gate.new(provider, questions:, thresholds:)`.**
  The questions a gate asks are a property of the host's tools, not of the gem.
  A booking tool and a shell tool are not dangerous for the same reason, and
  pi-jev's questions — "is this action destructive?", "does this send local data
  off-machine?" — say nothing useful about booking an appointment. A host now
  asks its own: "does this commit the customer to a booking?", "does this spend
  the owner's money?". Every question must be armed with a threshold, and a
  question without one is refused at construction rather than armed with a bar
  that never fires. A threshold given for one of the default questions still
  keeps the rest of the defaults, so raising one bar stays one line.

- **`OutputJudge.new(provider, questions:, advice:)`.** Same reasoning: what an
  output *is* — a leak, a failure class, the advice to give — belongs to the
  host. The two ids the result reads (`:leaks_secret`, `:failure_class`) stay
  the gem's contract, and the outcome question must offer `no_failure` among its
  criteria, because the judge runs after every judged call and not only after a
  suspicious one; both are refused at construction when they are missing, since
  a judge that reads nothing judges nothing, silently.

- **`AgentAdapter` passes the judgement through** — `gate_questions`,
  `output_questions`, `output_advice` — so a host configures the guards for its
  own tools in one place.

### Notes

- 0.2.0 is what it was released as: the router removal below, and the
  host-owned judgement arrived after it.

## [0.2.0] - 2026-09-17

### Removed

- **`Ask::Decisions::ToolRouter` — a router that picks one of N tools from the
  message alone.** It is gone because the measurement below is the argument
  against it: routing to a tool was right 10/16 where routing to a lane was
  right 19/20, on the same roster with the same model. Overlapping tools
  cannot be separated by a message — which of seven knowledge tools holds the
  answer is discovered by calling them — so a router answering that question
  is guessing with confidence. The lane withholds the tools a turn cannot
  need and the model chooses within the narrow roster, where it can see the
  candidates' results.

  Nothing in the ecosystem called it: not ask-agent, not ask-anychat, not any
  app. Take this as the cheap moment — the class has no users yet.

## [0.1.1] - 2026-09-18

The first release, so everything here is new. It is a decision layer for the
ask-rb ecosystem: ask Jev (or any System One model) typed questions and get
back answers with calibrated probabilities. LLMs generate text; deciders
decide.

### Added

- `Ask::Decisions::Reader` — asks a described set of options as one Choice,
  with anything else the caller needs riding along in the same request.
  `Triage` is a façade over it.
- `Ask::Decisions::Triage` — reads a message into a caller-defined lane and
  asks the mood and whether the person wants a human, all in one request.
  Measured against a 19-tool roster: lane-level routing was right 19/20 where
  tool-level routing was right 10/16 — the tools overlapped, and a lane is the
  part of the decision the message actually carries.
- `Ask::Decisions::AgentAdapter` — wires `Gate`, `OutputJudge`,
  `FailureClassifier`, `LoopDetector`, `QualityJudge`, `ReflectionJudge`,
  `ToolRepairer` and `ConfidencePolicy` into ask-agent's `before_tool` /
  `after_tool` hooks, so one config line activates the guard half:
  `Ask::Agent.configure { |c| c.decision_provider = :typesafe }`.
- `Ask::Decision::Choice`, `Score`, `Noul` primitives in ask-core
- `Ask::DecisionResult::ChoiceAnswer`, `ScoreAnswer`, `NoulAnswer`, `Batch` in ask-core
- `Ask::DecisionProvider` base class + registry in ask-core
- `Ask::Decisions::Typesafe` — HTTP client for TypeSafe/System One API
- `Ask::Decisions::Batcher` — one-call batching for parallel questions
- `Ask::Decisions::Cache` — MD5-keyed result caching (120s TTL)
- `Ask::Decisions::Static` — canned answers for tests
- `Ask::Decisions::Lint` — anti-pattern detection (8 rules, 2 measured from pi-jev)
- `Ask::Decisions::Gate` — pre-tool-call intent judge (4 calibrated questions)
- `Ask::Decisions::OutputJudge` — post-tool-call leak detection + failure classification (6 classes)
- `Ask::Decisions::FailureClassifier` — retry logic with attempt tracking
- `Ask::Decisions::ToolRouter` — Choice over tool roster + non-tool outcomes
- `Ask::Decisions::ArgumentResolver` — enum→Choice, bool→Noul, free text→generator
- `Ask::Decisions::DecisionState` — compact state projection with token budget
- `Ask::Decisions::ConfidencePolicy` — risk-tiered act/review/escalate thresholds
- `Ask::Decisions::LoopDetector` — Jev-based stuck/repeating detection
- `Ask::Decisions::QualityJudge` — composite scoring over rubric dimensions
- `Ask::Decisions::ReflectionJudge` — Noul-based self-critique
- `Ask::Decisions::ToolRepairer` — Choice over valid tool names + enum values
- `Ask::Decisions::Reranker` — Score per query-passage pair for ask-rag
- `Ask::Decisions::StructuredStateLoop` — OCR/DOM→Jev→action for ask-computer
- `Ask::Decisions::CalibrationReport` — reliability curves per decision id
- `Ask::Decisions::CalibrationHarness` — run test cases and measure calibration
- `Ask::Tools::Decide` — bridge tool for LLM agents (requires ask-tools)
- `Ask::Decisions::MCPHelper` — one-liner to add decide to MCP servers
- `Ask.decide` and `Ask::Decisions.batch` convenience methods
- Provider registry: `Ask::DecisionProvider.register`
- `ask-tools` `param :enum` support (backward compatible)

### Changed

- `Ask::Decisions::ToolRouter` takes `criteria:` — routing-grade descriptions,
  tool name to when to choose it — and a `limit:`. A tool's own description is
  written for the model that already holds the tool, so two accurate
  descriptions can still fail to separate their tools from the outside.
- `Triage::Verdict#wants_human?` requires the probability to be *above* the
  threshold. A noul at exactly 0.5 is the model saying it has no idea, which
  is the one answer that must not read as consent.
- Requires `ask-core >= 0.12.0` for the decision vocabulary.
