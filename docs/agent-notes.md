# Agent operational notes

Durable, verified facts for working on this cluster — distilled from things that cost real
investigation time. Each entry is something that was confirmed against source/binary, not
guessed. Prune session trivia; keep only what stays true.

## Doc lookup — Talos

Docs moved `talos.dev` → `docs.siderolabs.com` (2026). Old `www.talos.dev/v1.13/...` URLs 404.

- **Append `.md`** to any `docs.siderolabs.com` page URL → clean markdown (no JS shell).
- **URL index** (LLM-targeted list of all doc pages): https://docs.siderolabs.com/llms.txt
- Note the site reorganised paths too (e.g. reset is now under
  `.../configure-your-talos-cluster/lifecycle-management/resetting-a-machine`). Resolve paths
  via `llms.txt` rather than guessing.

Fallbacks when a page 404s or for version-exact truth:

- `talosctl <cmd> --help` — authoritative for the **installed** binary (v1.13.5).
- GitHub raw source (version-pinned):
  `raw.githubusercontent.com/siderolabs/talos/release-1.13/website/content/v1.13/<path>.md`
- Behaviour the docs gloss over → read the Go source under
  `internal/app/machined/pkg/controllers/` via `gh api '.../contents/<path>?ref=release-1.13'`
  (decode `.content` from base64).

## Talos / Kubernetes gotchas (verified, not guessed)

- **`machine.nodeTaints` SILENTLY no-ops on workers.** `NodeApplyController` runs on all nodes
  but PATCHes the Node with the _kubelet credential_ on workers; NodeRestriction hard-denies
  `"node %q is not allowed to modify taints"`. Use `machine.kubelet.extraConfig.registerWithTaints`
  instead — it's create-time (kubelet sets it at registration), which NodeRestriction permits.
  An already-registered node won't pick it up without re-registration → also `kubectl taint` once.
- **A taint ≠ a label.** `nodeSelector` matches **labels**. Pinning a workload to a tainted node
  needs `machine.nodeLabels` too. Custom-prefix labels (e.g. `mcf.io/`) are NOT NodeRestriction-
  blocked, so `nodeLabels` applies live via reconcile — no reboot, no re-registration (unlike the
  taint). Ordering trap: the label must exist on the live node BEFORE pushing a `nodeSelector`
  that references it, or the pod strands `Pending`.
- **Selective reset preserves data partitions.** `talosctl reset --system-labels-to-wipe
STATE,EPHEMERAL` wipes only those, keeps other partitions intact — the Rook OSD re-adopt path
  with no backfill. Worker→CP and CP→worker conversions both go through reset+reapply (machine
  type is effectively set at install).
- **RawVolumeConfig** creates a partition labelled `r-<name>`, **unformatted** — Rook's
  `devicePathFilter: /dev/disk/by-partlabel/r-csi-data` reuses it; the OSD survives a system-disk
  wipe untouched.
- **ExistingVolumeConfig** matches by **filesystem label**, not hostname/device — media disks
  survive a rename + system-disk wipe and re-mount by label.
- **Scheduler scoring** (k8s 1.36 defaults): TaintToleration weight **3** vs PodTopologySpread **2**.
  This cluster's machineconfig sets a cluster-wide PodTopologySpread default that pulls pods toward
  the emptiest host. A `PreferNoSchedule` taint nets only ~1 against that → a genuine soft nudge,
  not a wall. Bump TaintToleration weight in the scheduler profile if a harder push is ever wanted.
- **`kubernetesTalosAPIAccess` is correctly CP-only.** It mints an `os:admin` credential on the
  control planes; tuppr uses that one credential against every node's `apid` (workers included,
  validated via the shared machine CA). Workers need no Talos-API config to be upgradeable.
- **Per-node config patches deep-merge** into the templated `machine.kubelet.extraConfig` —
  sibling keys (GC thresholds, serializeImagePulls) survive. Verified via `talosctl machineconfig
patch`.

## Flux / GitOps / CNPG gotchas (verified, not guessed)

- **`flate diff` exits non-zero on a dangling `dependsOn`.** An unresolvable dependency renders as
  `flate error: ... reconcile completed with 0 failure(s) (+N blocked by failed/missing
dependencies)` and fails the CI job — it is NOT a benign offline artifact. Confirm with
  `FLATE_LOG_LEVEL=debug flate diff kustomization`, which prints
  `resource failed ... reason="dependencies failed: Kustomization/<ns>/<name>: dependency not
found"`. A health-gated CRD Kustomization that IS wired correctly renders fine offline (control
  case: `rook-ceph-cluster`'s `CephCluster` health-check on `main` → exit 0), so a `+N blocked`
  that appears only on your branch means a real broken dep name, not flate choking on the gate.
- **The CNPG operator's Flux Kustomization is named `cloudnative-pg`, not `cnpg`** (dir is
  `kubernetes/apps/cnpg-system/cnpg/`, but `metadata.name: cloudnative-pg`). `dependsOn` targets
  the Kustomization _name_, so `dependsOn: [{name: cloudnative-pg, namespace: cnpg-system}]`.
- **CNPG healthy phase literal is `Cluster in healthy state`** (from `api/v1/cluster_types.go`,
  `PhaseHealthy`). There is NO "failure state" phase — the unrecoverable one is
  `Cluster is unrecoverable and needs manual intervention` (`PhaseUnrecoverable`). Use these exact
  strings in Flux `healthCheckExprs` `current:`/`failed:` CEL for a CNPG `Cluster`.
- **`immediate: true` on a ScheduledBackup loses a startup race when the plugin stanza and the
  ScheduledBackup land in the same apply.** Adding `.spec.plugins` (barman-cloud) rolls the
  instance to inject the sidecar (native init container, `restartPolicy: Always`, ~1s); `immediate`
  fires before it's attached → a spurious `failed` Backup, `requested plugin is not available:
barman-cloud.cloudnative-pg.io`. Plugin discovery itself is fine — it's **annotation**-driven on
  the `barman-cloud` Service (`cnpg.io/pluginClientSecret` / `pluginServerSecret` / `pluginPort`;
  only `cnpg.io/pluginName` is a label), no operator-side cert mount needed despite the Helm chart
  exposing no volume knobs. Confirm registration via the Cluster's `status.pluginStatus`. Omit
  `immediate`; take a one-off `kubectl cnpg backup` for the initial recovery point instead.

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

## Cilium / NetworkPolicy gotchas (verified, not guessed)

- **`toFQDNs` for a short external host silently fails under the cluster's `ndots:5` +
  CoreDNS `autopath`.** A pod resolver defaults to `options ndots:5`; a 2-dot host like
  `mcfaul.cloudflareaccess.com` (< 5 dots) is therefore tried **search-expanded first**
  (`….<ns>.svc.cluster.local`). CoreDNS runs `autopath @kubernetes`, which answers that
  first expanded query directly with the _external_ record — so Cilium's DNS proxy only ever
  observes/caches the **expanded** name, and a policy selector `matchName:
mcfaul.cloudflareaccess.com` (bare) never matches. The resolved IPs get no FQDN identity →
  default-deny drops the connect → `connect: connection timed out` (NOT a DNS error; the
  lookup succeeds). Fix: pin `ndots:2` on the pod via `dnsConfig` so
  the host resolves as-is first and the proxy caches the bare name. `toEndpoints` (label) rules
  are immune — they don't touch the DNS proxy. **Cluster-wide:** ANY pod hitting
  a short external hostname under a `toFQDNs` policy fails identically. Give any such pod
  (e.g. a CI runner with egress to package/container registries) the same `ndots:2` (or a
  `matchPattern` selector) from the start.
- **Diagnose `toFQDNs` drops from the agent, not by guessing.** On the pod's node:
  `cilium-dbg fqdn cache list` shows exactly which _names_ the DNS proxy cached (reveals the
  search-expansion) and which IPs each maps to; `cilium-dbg policy selectors list` shows
  whether an FQDN selector programmed any IPs; `cilium-dbg ip list | grep <ip>` confirms
  whether the destination IP has an FQDN identity or fell through to `world` (→ dropped).
  `CNP VALID: True` means the policy _parsed_, NOT that its `toFQDNs` rule is matching.
- **The DNS proxy runs even with `envoy.enabled: false`.** Confirmed on the live agent:
  `enable-l7-proxy=true`, `dnsproxy-enable-transparent-mode=true`, full `tofqdns-*` config
  present despite Envoy being disabled in Helm values — the disabled component is the L7-**HTTP**
  proxy, a separate thing. Transparent DNS-proxy mode also means no first-resolution race (the
  proxy holds the response until the IP is programmed into the policy map). So `toFQDNs` is
  viable on this cluster; the `ndots` trap above is the only catch.
- **`toEndpoints` without a namespace label defaults to the policy's OWN namespace.** Same-ns
  targets (e.g. the CNPG `-rw` service by `cnpg.io/cluster` label) need no ns label; a
  cross-namespace target (e.g. CoreDNS in `kube-system`) MUST carry
  `k8s:io.kubernetes.pod.namespace: kube-system` or it silently won't match. And a `toFQDNs`
  rule REQUIRES an accompanying DNS egress rule (`toEndpoints` kube-dns + `toPorts` with
  `rules.dns` matchPattern) so the proxy observes the lookup — omit it and every FQDN policy
  fails closed.

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
