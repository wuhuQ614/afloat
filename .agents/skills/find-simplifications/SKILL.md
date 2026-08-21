---
name: find-simplifications
description: 'Use when working in this repo to find non-obvious simplification candidates, write proposed Agent Notes or inline TODO/FIXME/XXX notes, or fold worthwhile simplification ideas; especially for dead, duplicated, speculative, over-built, added-then-removed, or hand-rolled-where-a-dependency-exists surfaces.'
---

# Finding Simplifications

This skill helps turn a broad "find things to simplify" request into evidence-backed proposals that remove or collapse existing surface area. It is guidance, not a checklist: follow the code, keep judgment active, and prefer a few well-proven candidates over a pile of thin guesses.

## Start With Repo Context

- Read `AGENTS.md`, especially the conventions and the "tests are not golden truth" doctrine, plus `docs/defensive-patterns.md` and `docs/architecture.md` when present.
- Skim the architecture before judging anything under `lib/`; simplifications that fight the service map or state model need extra evidence.
- Treat intentionally duplicated native/FFI bindings and platform branches as intentional by default. Do not propose deleting either side as "low effort" unless the user explicitly overrides that constraint.

## What Counts As A Strong Candidate

A strong simplification removes, folds, or demotes something real and has clear evidence that the current design costs more than it buys:

- A public method, callback, config knob, notifier, helper, or test artifact has no production consumer.
- Tests or docs are the only consumers, and the behavior they pin is not load-bearing.
- Two representations mirror the same fact, especially across persisted state and transient UI state.
- A seam has methods every implementation must support but no consumer uses.
- A feature implements speculative product generality with no product owner.
- Hand-rolled code reimplements what a well-maintained package or a Dart/Flutter builtin already provides, and the swap would delete the implementation plus its dedicated tests.
- The simplified behavior may differ slightly, but the new behavior is still reasonable and easier to explain.

Thin candidates are usually not enough: deleting one typo, running a linter once, or flagging "this looks complex" without call-site proof.

## Survey Broadly

Use parallel subagents when the user asks for breadth or many candidates. Give each agent a domain and require evidence, not guesses. Useful domains:

- UI and navigation: widget rebuild boundaries, `ListenableBuilder` scope, `RepaintBoundary` placement, route lifecycle.
- State and persistence: `AppState` fields, `Storage` keys, `shared_preferences` migration, session resume.
- Native and FFI: `native/` C/C++ logic, Dart bindings in `services/`, struct field-layout stability.
- Services and API: `api_service.dart`, streaming, error handling, retry/backoff.
- Build, assets, and tooling: `pubspec.yaml`, `assets/`, CI scripts.

If subagents are unavailable, simulate the same breadth yourself. Do not let the first good candidate stop the survey.

## Audit Trust And Lifecycle Boundaries

For every defensive copy, freeze, validator, and callback capture, name where the value came from and who owns it next. Same-process typed calls ordinarily borrow readonly values; parsers, config loaders, queues, JSON, durable files, isolates, and platform channels own or validate their data. Tests built around hostile getters, fake typed objects, or mutation after a same-process handoff are evidence of a potentially speculative contract, not automatic justification for keeping it.

For complex asynchronous code, draw the ownership graph and map each `Ticker`/`AnimationController`/`StreamSubscription`/`Timer` to a distinct owner or transition. When several mechanisms mirror the same liveness or settlement fact, propose one lifecycle controller instead. Preserve separate machinery where it protects synchronous publication and rollback, callback containment, first-terminal-outcome arbitration, or dispose-to-quiescence.

## Hand-Rolled Code Versus A Dependency

Introducing a dependency is a valid simplification move, not a policy exception. When surveying, ask of retry/backoff loops, diff engines, caching layers, and similar infrastructure: does a well-maintained pub package or a Dart/Flutter builtin already do this?

Prove a dependency-swap candidate like any other, plus:

- Read the hand-rolled implementation and name the exact surface the package covers; residual semantics the package does not cover count against the swap.
- Check the package's health honestly (maintenance, adoption, transitive footprint).
- Weigh net deletion: implementation plus dedicated tests plus docs, minus the glue that remains. A wrapper that relocates the same complexity is not a win.

## Prove Or Reject Each Candidate

For every symbol or behavior, classify consumers before writing:

- Production corpus: `lib/**`, `native/**`, `bin/`, entry points, and `pubspec.yaml`.
- Non-production corpus: tests, README/docs, Agent Notes, generated mocks.
- Ambiguous corpus: examples and scripts that may be product smoke paths. Inspect usage before classifying.

Use `rg` first. Good searches include the exact symbol, method name with both `.name(` and `name(`, and any wire strings. Then read the call sites. A linter/unused-export check can help, but it is not a substitute for understanding public interfaces, dynamic dispatch, tests, and build paths.

Reject or downgrade a candidate when:

- A production caller exists and the simplification would be a feature decision rather than a cleanup.
- The API is explicitly justified by an implemented Agent Note or a hard-won defensive pattern, and the new evidence does not beat that reason.
- The removal would force unrelated churn without actually reducing the public API or required behavior.
- The idea is correct but tiny. Add a targeted TODO/FIXME/XXX instead, using the urgency semantics in `AGENTS.md`.

## Write The Proposal

Create one file per durable proposal under `.agents/notes/<lifecycle>/<class>/yyyy-mm-dd-topic.md`, following the lifecycle and classification rules in `.agents/notes/README.md` (when present). Prefer this structure:

- `# Agent Note: <action-oriented title>`
- `Status: proposed`
- `## Problem`: name the current API, cite the relevant files, and state the consumer evidence.
- `## Proposal`: say exactly what to remove, fold, demote, or rehome.
- `## Why not keep it?`: make the strongest counterargument legible.
- `## Acceptance criteria`: observable end state and gates.
- `## Risks`: public API changes, behavior changes, future product wants.

Be concrete enough that an implementing PR can follow the trail.

## Inline TODO Notes

Use inline TODO/FIXME/XXX only for small, local cleanups that are clearly useful but not durable design decisions. Keep them short and actionable:

- Name the smell with a stable tag, e.g. `TODO(double-default)` or `XXX(unused-default)`.
- Explain why it is safe to revisit and what action would simplify it.
- Do not add TODOs for speculative complaints or for behavior that needs an Agent-Note-level decision.

## Validation And PR Hygiene

For docs-only note work, run at least `flutter analyze` and `dart format`. For code changes, run the relevant test or build. Select any other evidence from the outgoing diff.

When opening or updating a PR, summarize:

- How many notes and inline notes were added, consolidated, or deleted.
- The main areas surveyed.
- What was intentionally excluded.
- Which checks passed.
