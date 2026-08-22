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

## bjw-s app-template chart gotchas (verified against chart source, not guessed)

- **A chart-managed `persistence` PVC (`type: persistentVolumeClaim`, no `existingClaim`) names
  itself after the bare release name, not the persistence key, unless there's more than one such
  PVC on the release.** Confirmed in `bjw-s.common.lib.determineResourceNameFromValues`
  (bjw-s-labs/helm-charts, tag `app-template-5.1.0`): the persistence key is only appended when
  `itemCount > 1` (counting PVC-type entries that aren't `existingClaim`) or
  `global.alwaysAppendIdentifierToResourceName` is set. An app with exactly one chart-managed PVC
  entry — e.g. a `cache` volume alongside a `config` volume that's an `existingClaim` — gets a
  generated PVC named after the release itself (`home-assistant`, not `home-assistant-cache`),
  which silently collides with any other PVC of that name (e.g. the app's real config PVC). Always
  set `suffix:` on a lone `persistentVolumeClaim` entry to force a distinct name — seerr's `cache`
  entry does this (`suffix: cache`) even though its key is already `cache`; the suffix isn't
  cosmetic, it's what prevents the collision. This bypassed local review once already (see PR
  #3680/#3681) and reached `main` live before being caught, because `flate build`/`flate diff`
  render the Helm _values_, not the chart's actual templated output — they cannot catch a PVC
  naming collision, only a real `helm template` or a running cluster can.
- **When fixing a naming collision like the above, pick a `suffix` that matches an existing PVC's
  name if one exists, not a fresh one.** If the app previously had a standalone PVC manifest for
  the same volume (protected from Flux prune via a `kustomize.toolkit.fluxcd.io/prune: disabled`
  label) and you're switching it to a chart-managed entry, name the new chart-managed PVC after
  the old standalone one. Helm then adopts the existing, already-populated PVC in place instead of
  minting an empty one and leaving the old one orphaned for manual cleanup.

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
- **`flate build ks cluster-apps` does not render per-app resources.** `cluster-apps` targets
  `./kubernetes/apps` as a plain Kustomize composition — its output is the Flux `Kustomization`
  _objects themselves_ (each app's `flux-kustomization.yaml`), not the contents of what those
  objects point to. Validating a per-app resource change (e.g. a `SnapshotPolicy` field) against
  `cluster-apps` shows zero matches even when the change is correct. Use the app's own named
  Kustomization instead — `flate build ks recyclarr`, `flate build ks zwave` — which resolves that
  app's `./resources` path plus its components and shows the real rendered output.

## kopiur backup/restore gotchas (verified against source and a live restore test, not guessed)

- **`Restore` objects with `target.pvcRef`/`target.pvc` ("direct" targets) are one-shot and
  destructive by default — never commit one to Git as a standing manifest.** Confirmed by reading
  the reconciler (`crates/controller/src/restore/{mod,plan}.rs`, kopiur tag `7c8dd3f`): once a
  direct-target `Restore` reaches `Completed`, that phase is terminal — it never re-checks the PVC
  or reruns, even on a `spec` change. It also never inspects whether the target PVC already has
  data: kopia's `overwriteFiles`/`overwriteDirectories`/`overwriteSymlinks` all default `true`, so
  pointing `pvcRef` at a live, populated PVC overwrites it unconditionally. Only `target.populator`
  treats `Completed` as non-terminal and gates on the PVC being unclaimed. The correct DR runbook:
  after a corrupted/deleted PVC is recreated empty (by Flux), run
  `kubectl kopiur restore --from-policy <app> --to-pvc <app> --wait` by hand — this creates an
  ephemeral, uniquely-named `Restore` object, never applied through Git.
- **`kubectl kopiur ls`/`cat`/`browse`/`download` need the `ClusterRepository`'s
  `encryption.passwordSecretRef.namespace` set explicitly**, even though the operator itself
  resolves an absent namespace fine (defaults to its own namespace via `KOPIUR_NAMESPACE`). Absent
  namespace errors with `references credential Secret "..." without a namespace, so it cannot be
located from a browse session`. Fix: pin `namespace: kopiur-system` (or wherever the operator
  runs) on the `ClusterRepository`'s `passwordSecretRef`.
- **A completed CronJob-owned Pod still blocks PVC deletion.** The `kubernetes.io/pvc-protection`
  finalizer waits for every Pod whose spec references the PVC to be gone — a `Succeeded` pod kept
  around by job history still counts. `kubectl delete pvc` hangs in `Terminating` with no events;
  `kubectl delete job <the-old-job>` (which owns the pod) unblocks it immediately. Verified during
  a real restore-round-trip test on `recyclarr` (a CronJob-backed app).
- **`mover.inheritSecurityContextFrom.pvcConsumer` copies the whole `PodSecurityContext`, not just
  UID/GID.** Confirmed against a live cluster: `matter-server`'s mover Job pod inherited the
  workload's pod-level `sysctls` entry (`net.ipv6.conf.net1.accept_ra_rt_info_max_plen`, meant for
  its Multus macvlan `net1` interface) even though the mover pod itself carries no Multus network
  annotation and never gets a `net1` at all. Every mover run then failed sandbox creation
  permanently (`FailedCreatePodSandBox`, runc reporting the missing-interface sysctl write as
  `"unsafe procfs detected"` rather than a plain ENOENT — a hardened-procfs-openat2 message shape,
  not a permissions issue). Any app-level pod sysctl that targets a secondary-CNI interface will
  break that app's kopiur backups this way. Fix: never put interface-scoped sysctls on
  `defaultPodOptions.securityContext.sysctls` for a pod with a Multus attachment — put them on the
  `NetworkAttachmentDefinition` instead, via a `tuning` CNI meta-plugin stage chained after the
  interface-creating plugin (e.g. `macvlan` → `sbr` → `tuning`). The `tuning` plugin binary ships in
  the same `cni-plugins` bundle already providing `sbr`.

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
