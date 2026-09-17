# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `Ask::Decisions::Reader` — asks a described set of options as one Choice,
  with anything else the caller needs riding along in the same request.
  `ToolRouter` and `Triage` are façades over it, so the two stop growing
  apart while keeping names that say what each one is for.
- `Ask::Decisions::Triage` — reads a message into a caller-defined lane and
  asks the mood and whether the person wants a human, all in one request.
  Measured against a 19-tool roster: lane-level routing was right 19/20 where
  tool-level routing was right 10/16 — the tools overlapped, and a lane is the
  part of the decision the message actually carries.

### Changed
- `Ask::Decisions::ToolRouter` takes `criteria:` — routing-grade descriptions,
  tool name to when to choose it — and a `limit:`. A tool's own description is
  written for the model that already holds the tool, so two accurate
  descriptions can still fail to separate their tools from the outside.
- `Triage::Verdict#wants_human?` requires the probability to be *above* the
  threshold. A noul at exactly 0.5 is the model saying it has no idea, which
  is the one answer that must not read as consent.
- Requires `ask-core >= 0.12.0` for the decision vocabulary.

## [0.1.0] - 2026-09-17

### Added
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
