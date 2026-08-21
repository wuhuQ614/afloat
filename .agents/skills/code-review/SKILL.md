---
name: code-review
description: Use when reviewing a pull request or a diff in this repo — orients the reviewer to this codebase's standards (AGENTS.md conventions, defensive patterns, ADRs, quality gates) and the review-specific checks that code alone can't show
---

# Reviewing a Pull Request

**This skill is guidance, not a complete checklist.** Verify and fetch the PR's live base and exact head, then understand the design before reading the diff and enough surrounding code. A short review with one substantiated blocker is better than a list of nits. Prioritize correctness, lifecycle, security, and broken required behavior over style.

## Sources of truth

- `AGENTS.md`: standing repository authoring rules and conventions.
- `docs/defensive-patterns.md` (if present): lifecycle, async-state, disposal, and platform bug classes.
- `docs/architecture.md` (if present): high-level module map and invariants.
- Agent Notes under `.agents/notes/` (if present): design rationale. Treat disagreement with a note as a design discussion, not an automatic veto.

## Blocking requirements

1. **New prose receives semantic review.** Critically review every added or changed comment, doc, prompt, diagnostic, and visible string. Verify accuracy and placement against the owning code or behavior; automated checks do not establish those properties.
2. **Docs match the code.** Config, defaults, errors, and public behavior update the affected README/doc in the same diff. Comments state non-obvious contracts; flag implementation narration, test walkthroughs, and duplicated rationale for deletion or a link to their one home.
3. **Registrations clean up.** Verify each new resource/listener/subscription passes disposal and teardown expectations.
4. **Required evidence exists.** Verify the author ran the relevant local checks for the diff (see `AGENTS.md`); review the semantic gaps neither can detect.
5. **No hidden configurability.** Deployment-varying choices are explicit parameters/settings, not a hardcoded constant with a comment claiming it is configurable.

## Manual checks

- **Intent and interface contracts:** trace both sides of every changed interface. Confirm the implementation matches the PR and any note, including errors, cancellation, ownership, and disposal.
- **Lifecycle and concurrency:** for async setup, streams, timers, animations, or teardown, apply defensive-patterns. Check races before publication, cancellation during awaits, independent error reporting, ownership before reentry, complete detach cleanup, and quiescent disposal (e.g. `Ticker`/`AnimationController`/`StreamSubscription` disposed in `dispose()`).
- **Capability and consumer fit:** trace every current consumer, then flag consumer-specific behavior leaking into a shared widget/service. A new public method whose only caller is one internal consumer is an unnecessary API expansion.
- **Scope, ownership, and necessity:** map each abstraction, state machine, option, defensive copy, and compatibility path to its current contract, production consumer, and owning module. Challenge unrelated features and speculative generality.
- **Configuration and public choices:** ask what current-consumer evidence supports each default, public operation set, or imported external concept. Require an explicit choice or deferral when that evidence is absent.
- **Real entry path:** tests exercise the shipped widget, service, or binary where relevant. A hand-mounted mock does not catch invalid builder exports or broken `build()` paths.
- **Test strength:** assertions fail on the intended regression and verify external state, logs, or disposal rather than restating the implementation or trusting an agent's report. Coverage is necessary but not evidence that the scenario is correct.
- **Transcript/UI changes:** editor-visible or user-visible changes update snapshots or explain why no snapshot applies.

## Reporting findings

State the defect, location, impact, and evidence. Place a localized defect inline on the tightest relevant diff range; use a PR-level comment for cross-cutting architecture, scope, or review-wide synthesis. Separate blockers from suggestions and omit issues already enforced by a green gate. When receiving review, verify each claim and fix or rebut it on technical grounds without performative agreement.
