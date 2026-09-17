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
- `Ask::Decisions::Lint` — anti-pattern detection (jaggedness list)
- `Ask::Decisions::Gate` — pre-tool-call gate with calibrated thresholds
- `Ask::Decisions::OutputJudge` — post-tool-call output screening and failure classification
- `Ask.decide` and `Ask::Decisions.batch` convenience methods
- Provider registry: `Ask::DecisionProvider.register`
