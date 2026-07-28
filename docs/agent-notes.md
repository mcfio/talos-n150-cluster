# Agent operational notes

Durable, verified facts for working on this cluster — distilled from things that cost real
investigation time. Each entry is something that was confirmed against source/binary, not
guessed. Prune session trivia; keep only what stays true.

- Talos machine-config gotchas (taints vs labels, selective reset, volume configs, scheduler
  weights) live in `talos/CLAUDE.md` — also relevant to `kubernetes/apps/*` manifests that
  select these nodes, not just to editing Talos config itself.

## Flux / GitOps / CNPG gotchas (verified, not guessed)

- **`flate diff` exits non-zero on a dangling `dependsOn`.** An unresolvable dependency renders as
  `flate error: ... reconcile completed with 0 failure(s) (+N blocked by failed/missing
dependencies)` and fails the CI job — it is NOT a benign offline artifact. Confirm with
  `FLATE_LOG_LEVEL=debug flate diff kustomization`, which prints
  `resource failed ... reason="dependencies failed: Kustomization/<ns>/<name>: dependency not
found"`. A health-gated CRD Kustomization that IS wired correctly renders fine offline (control
  case: `rook-ceph-cluster`'s `CephCluster` health-check on `main` → exit 0), so a `+N blocked`
  that appears only on your branch means a real broken dep name, not flate choking on the gate.
- CNPG-specific gotchas (Kustomization naming, health-check phase literals, ScheduledBackup
  plugin race) live in `kubernetes/apps/cnpg-system/CLAUDE.md`.

## Git / PR workflow gotchas (verified, not guessed)

- **PRs are squash-merged** (ruleset allows `squash`, `rebase`; squash is the practice).
  A squashed PR lands on `main` as ONE new commit with a fresh SHA; a local branch still
  descends from the pre-merge commit(s). Basing a follow-up on that local base → merge
  CONFLICT (same file introduced by two unrelated commits). Always `git fetch` and branch
  off `origin/main`; confirm merged content with `git show origin/main:<path>` first.
- **Squash can silently drop later commits of a multi-commit branch** if the merge fires
  against a branch state that predates the latest push. After every merge, re-verify each
  intended change reached `main` (`git show origin/main:<path> | grep <marker>`) rather
  than trusting a green PR. Prefer one-commit fix PRs.

## Code comment style

- Comments describe what the code does **now**, not its history. No "changed from X",
  "was Y", decision-narrative, or "see PR #123". One line per step; design rationale and
  history live in `docs/` or the plan file, not inline.

## Claude Code auto-mode / permissions (verified against docs)

- **`kubectl` allow rules only match verb-first — always invoke `kubectl <verb>` first.** Bash
  allow rules are literal prefix matches, so `Bash(kubectl get:*)` matches
  `kubectl get -n ns pods` but NOT `kubectl -n ns get pods` (a global flag before the verb breaks
  the prefix). A non-matching command falls through to the auto-mode classifier, which fails
  **closed** ("could not evaluate → blocking for safety") whenever the classifier's own model call
  is down on the LiteLLM proxy — so verb-second style manufactures spurious denials. Write
  `kubectl get -n ns …`, `kubectl logs -n ns …`, `kubectl exec -n ns …` — namespace/flags AFTER
  the verb. Same rule for any tool whose allow entry names a subcommand (`git`, `gh`, `helm`).
- **Compound commands match per-subcommand.** Recognized separators: `&&`, `||`, `;`, `|`, `|&`,
  `&`, newline. Every subcommand must match an allow rule or the whole line hits the classifier —
  one uncovered token (`python3`, un-pinned `curl`) drags the entire compound in. `cd` into the
  workdir is built-in read-only, but `cd && git …` always prompts regardless of target.
