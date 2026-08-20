# Agent operational notes

Durable, verified facts for working on this cluster — distilled from things that cost real
investigation time. Each entry is something that was confirmed against source/binary, not
guessed. Prune session trivia; keep only what stays true.

- Talos machine-config gotchas (taints vs labels, selective reset, volume configs, scheduler
  weights) live in `talos/CLAUDE.md` — also relevant to `kubernetes/apps/*` manifests that
  select these nodes, not just to editing Talos config itself.

## Nushell / mise task gotchas (verified against nu 0.115.0 and mise, not guessed)

`talos/talos.nu` holds the node-management logic; `talos/.mise.toml` tasks are argument shims that
`use` it. `kubernetes/.mise.toml` is still bash.

- **`unix_default_inline_shell_args` is IGNORED outside the global config.** Setting it in
  `.mise/config.toml` produces `mise WARN unix_default_inline_shell_args in non-global config … is
ignored for security reasons`. It only works in `~/.config/mise/config.toml`. So repo-level tasks
  get mise's default `sh -c` unless a task sets `shell` itself — which IS honoured per-task in a
  repo config. Don't re-add the global line; use `shell = "…"` on the task.
- **`--no-config-file` on every nu task shell.** Without it nu sources the operator's personal
  config, which is a reproducibility hazard on a recovery path. Startup is ~27 ms either way.
- **Piping a record or table to an external command emits the box-drawing table, not data.**
  `{a:1,b:2} | ^cat` prints `╭───┬───╮`. Every hand-off to `talosctl`/`op` needs an explicit
  `| to yaml`. Silent-corruption class of bug — the external sees valid-looking text.
- **`from yaml` shape depends on document count**: a record for single-document input, a list for
  multi-document. Normalize with `describe --detailed` before indexing, or a single-doc node file
  silently takes a different path. `talos.nu`'s `yaml-docs` exists for exactly this.
- **Multi-document YAML does not round-trip.** `to yaml` emits a YAML _sequence_, not `---`-
  separated documents. Nu can read fields out of a Talos config; it must never write one back —
  `talosctl machineconfig patch` stays the merge engine.
- **Non-zero external exit is a hard error** (nu ≥ 0.98). That's `set -e` for free, and why
  `cmd || exit 0` idioms become `try`/`catch`.
- **`complete` captures stderr, so it breaks any TUI.** `(^gum confirm … | complete).exit_code`
  returns the right code but the prompt is invisible. Use `try { ^gum confirm …; true } catch
{ false }` — `try` leaves the child's streams attached.
- **`$env.FILE_PWD` is unset inside `use`d modules** and errors on access. `const HERE = path self .`
  is the working form for a module locating files beside itself.
- **`str substring 0..8` yields 9 characters.** Use `0..<8` to match bash's `${VAR:0:8}`.
- **mise `usage` args arrive as env vars** (`$env.usage_node`), so they work from any interpreter.
  Var-args arrive as ONE string — `split row " "` then splat, which word-splits exactly as the old
  `${usage_args[@]:-}` did.
- **There is no template engine any more.** `cluster.yaml` carries exactly one substitution,
  `{{ schematic_id }}`, done with `str replace`; `controlplane.yaml` carries none.
- **`open --raw <file> | ^external` gives the external a REGULAR FILE on stdin, not a pipe.** Nu
  hands the opened file's own fd straight to the child. `op inject` requires a pipe and rejects it
  with `expected data on stdin but none found` — a message that reads like an auth or empty-input
  problem and sends you the wrong way. Any transformation in the chain (`str replace`, `into
string`) forces materialization and produces a real FIFO, so the two calls in `render` behaved
  differently for the same-looking code. Verified with `stat -L -f %HT /dev/stdin`: form 1
  `Regular File`, form 2 `Fifo File`. Prefer the tool's own file-input flag (`op inject -i`) over
  relying on an incidental transformation to create the pipe.
- **`op inject` rejects any non-`op://` `{{ }}`** — `parsing error: only secret references or
quoted strings can be enclosed in unescaped {{ }}s`. Template substitution MUST run before it,
  and op parses before it authenticates, so this fails identically signed-in or not.
- **A `sed`/`cat` stub for `op` cannot validate this path.** They read any fd kind, so stubbed
  renders pass while the real command fails. Byte-parity harnesses prove the _layering_ is right,
  never that the secret plumbing works — that needs one real render.
- **`complete` only captures the FINAL external of a pipeline.** `do { inner } | complete` where
  `inner` is a custom command whose _non-final_ stage fails returns `exit_code: 0` and empty
  `stderr`, with the real error leaking to the terminal. `--capture-errors` does not help — it
  returns a nu error value, never the child's stderr. To attribute a failure, `complete` the stage
  itself: `^cmd … | complete | check "cmd"`. That is what `talos.nu`'s `check` helper is for.
- **Never `complete` a command that may prompt for auth.** Same trap as `gum` — `op` can need
  interactive approval, and capturing its stderr would make the prompt invisible on a recovery
  path. `render` captures `talosctl` (never interactive) and leaves `op`'s streams attached.
- **Nu appends a newline when a string is redirected to a file, but pipes a string to an external
  verbatim.** `talosctl machineconfig patch` terminates its output with `\n\n`, so `complete`'s
  `stdout` must have exactly one trailing newline stripped (`str replace --regex "\n$" ""`) to stay
  byte-identical to the streaming form on `render-config > file`. `str trim --right` is wrong — it
  eats both. Consequence: the file-redirect path is byte-exact and the pipe-to-external path is one
  trailing newline short. Verified byte-identical across all four nodes.
- **Nu wraps table cells to terminal width, which destroys any alignment built inside a cell.**
  There is no `table` flag for truncation — it is config-only (`$env.config.table.trim`), and
  config set inside a module `def` never reaches the caller's renderer, so a module cannot opt in
  on its own. `talos diff` truncates each line itself against a budget derived from `term size`
  (`term size` reports 0 columns with no terminal; 80 is nu's own default). A `--width` flag sizes
  cells only, never the renderer, so it is meaningful solely when paired: `talos diff --width 200
| table --width 200`.
- **A bare `-` inside a list literal is parsed as a string element, not as subtraction.**
  `[(($a - $b) // 2) - 5 20] | math max` silently yields `"-"` and then fails with
  `can't convert string to int` somewhere else entirely. Parenthesize the whole arithmetic
  expression: `[((($a - $b) // 2) - 5) 20]`.
- **`talosctl apply-config --dry-run` writes its summary AND the config diff to stderr**, not
  stdout. Capturing only stdout yields an empty string, which reads as "no changes" while the real
  diff leaks past the formatter onto the terminal — a false clean bill of health. `talos diff`
  captures both streams via `complete`. A stub that emits on stdout cannot catch this: stub an
  external on the stream the real tool actually uses, or the harness is blind by construction.
- **Filter unified-diff headers as `--- ` / `+++ ` with the trailing space.** In a Talos config
  diff a removed `---` document separator renders as `----`, which a bare `str starts-with "---"`
  silently drops from the changed-line count.
- **`talosctl validate --strict` is a schema check, not a secret check.** A config whose every
  `op://` ref resolved to the literal `Zm9vCg==` validates clean — certs are only base64-decoded,
  never parsed. It catches unknown keys and wrong types; it cannot tell you the secrets are right.
- **Nu switch flags accept `--flag=true|false`**, which is how a mise `usage` flag threads through:
  `talos diff $env.usage_node --wide=(($env.usage_wide? | default "") == "true")`. Compare against
  the string rather than `into bool`, which errors on an empty value.
- **Renovate finds the Talos version by file glob.** The `talosFactory` preset scans
  `talos/**/*.ya?ml` for `factory.talos.dev/…:<version>`. The image tag must stay in a YAML file
  under `talos/` — moving it into `talos.nu` silently kills upgrade PRs with no error anywhere.
- **`talosctl machineconfig patch --patch` is a repeatable `stringArray`** accepting `@file` or an
  inline YAML string, applied in order, and an inline patch MAY be multi-document — that's how the
  control-plane overlay adds `Layer2VIPConfig` without a temp file. Verified on talosctl v1.13.8.
- Nushell is pre-1.0 on a ~4–8 week cadence and minor releases routinely break scripts (0.98 exit
  codes, 0.105 cell-path case sensitivity, 0.113.1 YAML quoting, 0.114 `--` parsing). It's on
  Homebrew, unpinned, by choice — `aqua:nushell/nushell` resolves in mise if that ever bites.

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

## Rook-ceph / RBD trash gotchas (verified, not guessed)

- **`rook-ceph-mgr` logging `[errno 39] RBD image has snapshots (error deleting image from
trash)` on repeat is expected steady-state noise, not a leak — do not "fix" it by purging
  snapshots or forcing trash removal.** Root cause: `kubernetes/components/volsync/pvc.yaml`
  provisions every app's live PVC via `dataSourceRef: {kind: ReplicationDestination}` against
  the permanent `${app}-restore-once` object in `replication-destination.yaml` (`trigger.manual:
restore-once` is a hardcoded string, so it fires once and never again). CSI populates the PVC
  as a **clone** of that restore snapshot and it is never flattened — a deliberate, permanent
  parent→child pin for the life of the PVC. When an old generation of that chain later gets
  trashed (PVC recreated, app rebuilt, etc.), Ceph correctly refuses to purge it because a live
  descendant still depends on it. Traced end-to-end on `home-assistant`: its live PVC image
  (`csi-vol-8ebfe5cb...`, created 2025-07-03) is still a clone of a snapshot on an image trashed
  the same day — over a year old, by design.
- The theoretically-correct remediation is `rbd flatten` (online-safe, `deep-flatten` is already
  in the storage class's `imageFeatures`) run against every live app PVC image to sever the
  parent link and let the mgr's own trash-purge succeed. Deliberately **not done** — full-copy
  I/O across every live app's data for zero functional benefit beyond quieter mgr logs. Revisit
  only if the trash backlog itself becomes a real problem (e.g. capacity pressure), not for log
  noise alone.
- Don't try to reach a trashed image's snapshots through `rbd snap purge --image-id`/`snap ls
--image-id` expecting it to behave like the named-image form — snapshots blocked by a live
  clone get moved into the RBD **TRASH snapshot-namespace type** (distinct from RBD pool
  namespaces), invisible to plain `snap ls` (needs `-a/--all`) and not reachable by name via
  `snap unprotect --snap <name>` (ENOENT) even though `snap rm --snap-id <id>` finds them (and
  then correctly refuses with "protected from removal" if a live child exists — `--force` isn't
  even accepted together with `--snap-id`). If ancestry ever needs to be cut, `rbd flatten` on
  the live child is the sanctioned path, not snapshot surgery on the trashed parent.

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
