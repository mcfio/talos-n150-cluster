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

- `talosctl <cmd> --help` — authoritative for the **installed** binary (v1.13.5). Settled the
  reset flags this session when web docs were unreachable.
- GitHub raw source (version-pinned):
  `raw.githubusercontent.com/siderolabs/talos/release-1.13/website/content/v1.13/<path>.md`
- Behaviour the docs gloss over → read the Go source under
  `internal/app/machined/pkg/controllers/` via `gh api '.../contents/<path>?ref=release-1.13'`
  (decode `.content` from base64). This is how the nodeTaints/NodeRestriction question got settled.

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
