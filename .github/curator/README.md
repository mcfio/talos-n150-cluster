# PR Curator — architecture and facts

Durable reference for the Renovate PR auto-merge curator. Facts, not narrative.
The workflow is `.github/workflows/pr-curator.yaml`; policy is `policy.yaml`;
classifier instructions are `prompt.md`.

## What it does

Classifies eligible Renovate PRs and enables GitHub auto-merge on a `safe`
verdict. Everything else is labelled `curator/needs-human` and left for a human.
Renovate still auto-merges its own predefined tier independently; the curator
only acts on what Renovate did not.

## Two-layer design (the core principle)

1. **Deterministic pre-gate (`policy.yaml`, enforced in the workflow).** Decides
   eligibility from labels + changed paths + flate conclusion. Anything excluded
   here NEVER reaches the model. This holds the real veto.
2. **LLM classifier (`prompt.md`, run via LiteLLM).** Only judges PRs the
   pre-gate already deemed eligible. It can veto (`needs-human`) but never
   promote — it cannot approve anything the pre-gate excluded.

The LLM is a constrained function (schema-pinned `{verdict, rationale}`), not an
agent. It has no tools and takes no actions. All actions (merge, label, comment)
are taken by deterministic workflow code.

## Why the pre-gate is non-negotiable

The model cannot see blast radius that isn't in the diff. A Talos version bump
(`v1.13.5 → v1.13.6`) renders as a trivial two-line version-string change but
`powercycle`-reboots every node. Asked directly, the model calls it `safe` — the
reboot implication isn't in the diff. `policy.yaml` excludes `^talos/` and
`kubernetes/apps/system-upgrade/` so it never reaches the model. Same reasoning
for storage/CNI/CRD/RBAC. **Do not move exclusions into the prompt** — that makes
the highest-blast-radius decisions probabilistic.

## Pipeline (in order)

1. **Resolve identity** — PR number from the `workflow_run` event; scope from the
   PR **author** (`gh api .../pulls/N` → `.user.login`), NOT `workflow_run.actor`.
2. **Gather** — PR metadata + full body → `pr.json`; flate diffs → `diff.md`.
3. **Policy gate** — read `policy.yaml`, first match wins. Ineligible → leave for
   human, stop.
4. **Fingerprint** — `sha256(prompt + diff + pr.json)` stored as a hidden marker
   in the sticky comment. Unchanged fingerprint → skip the whole LLM pipeline.
5. **Summarise** — LiteLLM call: distils the raw Renovate body (can be ~57k
   chars) into `{package, from, to, flags[], summary}` per package.
6. **Classify** — LiteLLM call: reads diff + changelog summary → `{verdict,
rationale}`.
7. **Apply** — `safe` → `gh pr merge --auto` + comment; else label + comment.
8. **Upsert comment** — one sticky comment (`header: curator`), replaced on
   re-runs, not appended.

## Two-step LLM pipeline

The classifier receives the compact per-package **summary**, never the raw body.
`flags` (`breaking_change`, `config_change`, `deprecation`, `cve_fix`) is the
authoritative signal — the summariser already analysed the changelog. The
classifier must TRUST empty flags and not re-analyse summary prose (doing so
recreates over-conservatism). This division of labour is stated in `prompt.md`.

The raw body is untrusted third-party changelog text (any upstream maintainer
whose package Renovate bumps can write it). The summarise step wraps it in
`<pr_body>` tags and instructs the model to treat everything inside as data, never
as instructions — a first-pass guard against changelog prompt injection. The real
bound stays structural: the LLM is a veto that can't promote past `policy.yaml`,
and `hk`+`flate` still gate the merge.

## Fail-closed (invariant)

The merge path fires ONLY on an explicit, schema-validated `verdict == "safe"`.
Every other outcome — network error, timeout, non-2xx, malformed body, summariser
failure, budget cap — routes to `needs-human`. Never branch on `!= "needs-human"`.
No `|| true` on the curl or the parse. A broken pipeline leaves the PR for a human;
it never auto-merges. `needs-human` is a NORMAL outcome (not auto-merged, review
at leisure), NOT a failure — there is no red status check for it.

## Trust / blast-radius model

Two independent gates decide whether the privileged job acts, in order:

1. **Capability** (job-level `if`): `workflow_run.head_repository.fork == false`. A
   fork-originated run never mints a token or runs a step — the branch must live in
   this repo, which needs write access. This is the everyday fork-PR control.
2. **Identity** (`is_bot`): the PR author's `.user.login` equals the login derived
   from the token's own app (`<app-slug>[bot]`). Routes non-bot PRs to a human.

Neither is the real trust boundary — the author gate is a routing decision, and even
if bypassed the worst case is auto-merge _enabled_ on a PR that still must pass the
required checks. The load-bearing controls:

- Bot (`purpose-robot`) is REMOVED from the ruleset `bypass_actors`. Even a
  compromised token cannot merge anything failing `hk` + `flate`. "Enable
  auto-merge" ≠ "merge" — GitHub's engine merges, gated by branch protection.
- App scoped to this repo only; minimum permissions (no admin/members read;
  packages read-only). The curator token holds `contents:write` (to enable
  auto-merge) + `pull-requests:write`.
- There is NO `curator/verdict` required status check. Auto-merge is enabled by
  the curator on `safe`; the required checks that gate the actual merge are
  `hk` + `flate (kustomization)` + `flate (helmrelease)`.

## Infrastructure

- **LiteLLM** in-cluster (`kubernetes/apps/default/litellm/`). `curator-model`
  alias routes to the cheap tier (Copilot `gpt-4o-mini`). Same alias for both
  summarise and classify.
- **External access:** second HTTPRoute `litellm.mcf.io` on the `external`
  gateway (internal route `litellm.milton.mcf.io` unchanged). Fronted by a
  Cloudflare Access **service token** (Service Auth policy) — machine-only.
- **GitHub secrets:** `LITELLM_API_KEY` (scoped, budget-capped virtual key),
  `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`; var `LITELLM_BASE_URL`.
  Reuses `BOT_APP_ID` / `BOT_APP_PRIVATE_KEY`. No `ANTHROPIC_API_KEY` anywhere
  (Copilot-backed).

## Verified gotchas

- **`workflow_run.actor` ≠ PR author.** It's whoever triggered the latest run
  (e.g. a human clicking "update branch"). Scope on the PR author instead.
- **`gh pr view --json author` gives `app/purpose-robot`; REST `.user.login`
  gives `purpose-robot[bot]`.** The guards use the REST form, comparing against a
  login **derived from the token's own app** (`app-token` `app-slug` output →
  `<slug>[bot]`), not a hardcoded string — it tracks an app rename or ID rotation.
  `Resolve identity` computes this once as `is_bot`; every step gates on that. The
  fingerprint scan reuses the same derived login so only the curator's own comment
  is trusted for the skip marker.
- **`workflow_run` triggers only fire from the DEFAULT-branch workflow
  definition.** A curator change must be on `main` before it affects any PR.
- **The model returns markdown-fenced JSON despite `response_format`.** Strip
  ` ```json … ``` ` in the jq validation before `fromjson`.
- **Large raw bodies break classification** (context overflow / fenced output).
  The summarise step exists to avoid feeding raw notes to the classifier.
- **oxfmt vs yamllint on regex quoting:** yamllint `only-when-needed` wants
  bare regexes; oxfmt accepts bare. Keep `policy.yaml` regexes unquoted. A regex
  starting with a YAML-special char (`*&!{[@\``) would need quotes + a yamllint
  ignore.

## Local testing

Secrets via 1Password; the pipeline is two curl calls. Build request bodies with
`jq --rawfile` (NOT `--arg` — a 57k body or a diff starting with `---` breaks
`--arg`) and pass to curl with `--data @file` (NOT inline `$var` — fish/bash
word-splitting mangles it). Strip the response fence with a `.jq` file, not an
inline expression (shell eats the `\\s`). See the workflow steps for the exact
request shapes.

## Extraction to a TS action

Considered and declined. The policy/prompt/tuning are cluster-specific, so a
generic action would parameterise away its own encapsulation. Revisit only if the
logic is needed in a second repo, or the pipeline grows to 3+ conditional LLM
calls. The seam to replace first would be the repeated LiteLLM curl (extract to a
composite action within this repo before reaching for TS).
