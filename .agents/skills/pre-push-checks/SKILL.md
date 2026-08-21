---
name: pre-push-checks
description: Use before pushing, force-pushing, marking ready for review, or claiming checks pass on a branch, to select the smallest tests and checks that cover the outgoing diff without reflexively running the full repository suite
---

# Pre-Push Checks

Use this skill to run relevant local evidence once before a push. CI owns exhaustive coverage and the platform matrix; locally run only the narrowest set that would fail for the diff's regression.

## Inspect the outgoing change

1. Confirm the checkout and branch.

```sh
git status --short --branch
git rev-parse --show-toplevel
```

2. Verify the live PR base or stack parent, fetch that ref, and inspect the complete scope against it.

```sh
git diff --stat <verified-base-ref>...HEAD
```

Never guess the base. Supply the ref verified from current remote or stack state. After merging a changed base, rerun the report and rerun only checks invalidated by the merge.

## Select relevant evidence

There is no universal local baseline beyond the hooks. Every behavior change needs the narrowest available test or purpose-built check that would fail for its regression; add broader checks only for surfaces the diff actually reaches.

- **Dart/Flutter behavior:** run the owning `flutter test` file or focused test name. Leave repository-wide coverage to CI unless the change is genuinely cross-cutting or the user requests it.
- **Documentation, Agent Notes, or doc-linked comments:** validate the affected docs; run lint when the doc workflow requires it.
- **Widget-/UI-visible output:** run the focused widget test or integration scenario that owns the output.
- **Native (C/C++) changes under `native/`:** rebuild the affected library and run its consumer; verify the FFI binding struct has not changed field layout when the Dart side relies on it.
- **Package manifests, public exports, build configuration, or binary entries:** run `flutter analyze` and the relevant build (`flutter build windows` / `flutter build apk`).

Do not manually repeat a passing check merely because commit or push follows. In particular, do not run `flutter analyze` immediately before pushing solely to duplicate the pre-push hook.

### Focus coverage on the affected source

When unit coverage is relevant, name both the owning tests and the source files whose coverage those tests must prove. Run only the packages/files the diff touches.

## Full local rehearsal

Run the complete local approximation only when the user explicitly requests it, while diagnosing a CI failure, or when the change spans the repository so broadly that no narrower set is credible.

## Protect history-rewriting pushes

Rebase is allowed for standalone and stacked PR branches, including after review. Before a standalone history rewrite, fetch the current remote branch and record its exact OID; publish with `--force-with-lease=<branch>:<observed-oid>` so a concurrent update aborts the push. Raw `--force` is never allowed.

After any rewritten push, fetch the live heads again and re-audit unresolved review threads, approvals, mergeability, and checks. Commit hashes and inline-comment anchors from before the rewrite are not current evidence.

## Handle failures

If a relevant check fails before an ordinary push, stop and fix or explain the blocker. Do not push and hope CI differs.

If a failure looks environment-specific, prove it:

- Record the exact command, failing test, and platform-specific mismatch.
- Confirm the relevant non-platform evidence.
- Prefer fixing cross-platform nondeterminism when the check is required.
- Bypass a local hook only when the user explicitly asks or agrees, and report exactly what failed and why CI is expected to differ.

## Push procedure

For ordinary and standalone rebase pushes:

1. Run the selected relevant checks once.
2. Commit normally and inspect any files changed by the pre-commit fixer before continuing.
3. Push normally, or use the exact lease for an authorized rewritten branch.
4. Verify the remote ref matches local `HEAD`.

```sh
git rev-parse HEAD origin/$(git branch --show-current)
```

Report pending checks as pending. Inspect failures before attributing them to the branch or the environment.
