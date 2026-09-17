# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
