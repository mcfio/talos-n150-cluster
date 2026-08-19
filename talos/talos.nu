# Talos node management.
#
# Machine configs layer in order: cluster.yaml (every node) -> controlplane.yaml (control planes
# only) -> nodes/<node>.yaml. `talosctl machineconfig patch` does the merging; nothing here
# serializes a machine config, because `to yaml` cannot emit multi-document YAML.
#
# The shared layers resolve once per command and are passed down to each `render`, so a run over
# every node costs one factory POST and one `op inject` per shared layer, not one per node.

const HERE = path self .

# Parse YAML into a list of documents. `from yaml` yields a record for single-document input and a
# list for multi-document input, so the shape has to be normalized before indexing.
def yaml-docs []: string -> list<any> {
  let parsed = ($in | from yaml)
  if (($parsed | describe --detailed).type == "record") { [$parsed] } else { $parsed }
}

# The v1alpha1 document, the one carrying the `machine` key.
def machine-doc []: string -> any {
  yaml-docs | where {|doc| ($doc | get --optional machine) != null } | get --optional 0
}

# Prompt before a destructive action. `complete` would capture gum's TUI off stderr and leave the
# prompt invisible, so the exit code comes from `try`/`catch` instead.
def confirm [message: string]: nothing -> bool {
  try { ^gum confirm $message --default=No; true } catch { false }
}

# Path to a node's config patch.
def node-patch [node: string]: nothing -> path {
  let file = $"($HERE)/nodes/($node).yaml"
  if not ($file | path exists) {
    error make {
      msg: "no such node"
      label: { text: $"no config patch at ($file)", span: (metadata $node).span }
    }
  }
  $file
}

# Whether a node's patch declares a control-plane machine type.
export def is-controlplane [node: string]: nothing -> bool {
  (open --raw (node-patch $node) | machine-doc | get --optional machine.type | default "worker") == "controlplane"
}

# Schematic ID from the Talos image factory. `http post` parses the JSON response by content type.
export def schematic-id []: nothing -> string {
  http post --content-type application/yaml https://factory.talos.dev/schematics (open --raw $"($HERE)/schematic.yaml")
  | get id
}

# Fail with an external's own first line of stderr rather than nu's generic non-zero-exit error.
# Exactly one trailing newline is stripped, because nu re-appends one when the string is printed
# or piped — stripping all of them would not round-trip talosctl's own `\n\n` terminator.
def check [stage: string]: record -> string {
  let r = $in
  if $r.exit_code != 0 {
    error make { msg: $"($stage) failed: ($r.stderr | first-line)" }
  }
  $r.stdout | str replace --regex "\n$" ""
}

# First non-blank line of an external's output, for one-line error and table cells.
def first-line []: string -> string {
  $in | lines | where {|l| ($l | str trim) != "" } | get --optional 0 | default "no output"
}

# The control-plane overlay with its secrets resolved. op's streams stay attached so an auth prompt
# remains visible. `op inject -i` is required because op reads only a pipe, and nu hands an external
# the opened file's own fd rather than a pipe.
def controlplane-overlay []: nothing -> string {
  ^op inject -i $"($HERE)/controlplane.yaml"
}

# Layers shared by every node, resolved once. `schematic_id` is substituted before `op inject` so op
# never sees a stray `{{ }}`. The overlay is resolved only when the run actually contains a control
# plane, so a worker-only render costs one `op inject`.
def resolved-layers [with_controlplane: bool]: nothing -> record<base: string, controlplane: string> {
  {
    base: (
      open --raw $"($HERE)/cluster.yaml"
      | str replace --all "{{ schematic_id }}" (schematic-id)
      | ^op inject
    )
    controlplane: (if $with_controlplane { controlplane-overlay } else { "" })
  }
}

# Render a node's full machine config, reusing pre-resolved shared layers when given. The base
# config carries secrets and goes over stdin; the resolved control-plane overlay is passed as an
# argument, so it is visible in this machine's process table while talosctl runs.
export def render [node: string, layers?: record]: nothing -> string {
  let cp = (is-controlplane $node)
  let shared = (if $layers == null { resolved-layers $cp } else { $layers })
  let patches = (
    (if $cp {
      # Pre-resolved when the caller passed layers for a run that contains a control plane.
      let overlay = (if ($shared.controlplane | is-empty) { controlplane-overlay } else { $shared.controlplane })
      ["--patch" $overlay]
    } else { [] })
    | append ["--patch" $"@(node-patch $node)"]
  )
  $shared.base
  | ^talosctl machineconfig patch /dev/stdin ...$patches
  | complete
  | check "talosctl machineconfig patch"
}

# The installer image a node's rendered config pins.
export def machine-image [node: string]: nothing -> string {
  render $node | machine-doc | get machine.install.image
}

# Names of every node declared in the repo.
export def node-names []: nothing -> list<string> {
  ls $"($HERE)/nodes/*.yaml" | get name | path parse | get stem | sort
}

# Talos version pinned by the base config's installer image.
export def config-version []: nothing -> string {
  open --raw $"($HERE)/cluster.yaml"
  | parse --regex 'factory\.talos\.dev/[^:]+:(?<version>v\S+)'
  | get version.0
}

# Live cluster membership, or an empty list when the cluster is unreachable. Only the call is
# guarded, so a change in talosctl's output shape surfaces instead of reading as "offline".
def members []: nothing -> list<any> {
  let out = (try { ^talosctl get members --output yaml } catch { null })
  if $out == null { return [] }
  $out
  | yaml-docs
  | each {|m| {
    node: $m.metadata.id
    type: $m.spec.machineType
    running: ($m.spec.operatingSystem | parse --regex '\((?<v>v[^)]+)\)' | get --optional v.0 | default "?")
  } }
}

# Live machine stage and readiness, or an empty list when the cluster is unreachable.
def machine-status [names: list<string>]: nothing -> list<any> {
  let out = (try { ^talosctl get machinestatus --nodes ($names | str join ",") --output yaml } catch { null })
  if $out == null { return [] }
  $out | yaml-docs | each {|s| { node: $s.node, stage: $s.spec.stage, ready: $s.spec.status.ready } }
}

# Inventory of declared nodes joined with live cluster state. Degrades to the repo's view alone
# when the cluster is unreachable, which is the state you are in during a recovery.
export def nodes []: nothing -> table<node: string, type: string, pinned: string, running: string, stage: string, state: string> {
  let pinned = (config-version)
  let names = (node-names)
  let live = (members)
  let status = (machine-status $names)
  $names | each {|n|
    let declared = (if (is-controlplane $n) { "controlplane" } else { "worker" })
    let m = ($live | where node == $n | get --optional 0)
    let s = ($status | where node == $n | get --optional 0)
    let running = (if $m == null { null } else { $m.running })
    {
      node: $n
      type: (if $declared == "controlplane" { $"(ansi cyan)($declared)(ansi reset)" } else { $"(ansi default_dimmed)($declared)(ansi reset)" })
      pinned: $pinned
      running: (if $running == null { $"(ansi default_dimmed)—(ansi reset)" } else if $running == $pinned { $running } else { $"(ansi red)($running)(ansi reset)" })
      stage: (if $s == null { $"(ansi default_dimmed)—(ansi reset)" } else if $s.ready { $"(ansi green)($s.stage)(ansi reset)" } else { $"(ansi yellow)($s.stage) not ready(ansi reset)" })
      state: (
        if $running == null { $"(ansi default_dimmed)offline(ansi reset)" }
        else if $running == $pinned { $"(ansi green)✓ current(ansi reset)" }
        else { $"(ansi yellow)⚠ drift(ansi reset)" }
      )
    }
  }
}

# Validate every node's rendered config offline. `--config /dev/stdin` keeps resolved secrets out
# of any file on disk. A node that fails to render is reported, not fatal.
export def validate []: nothing -> table<node: string, result: string, detail: string> {
  let names = (node-names)
  let shared = (resolved-layers ($names | any {|n| is-controlplane $n }))
  $names | each {|n|
    let rendered = (try { { ok: true, config: (render $n $shared) } } catch {|e| { ok: false, config: $e.msg } })
    if not $rendered.ok {
      { node: $n, result: $"(ansi red)✗ render(ansi reset)", detail: ($rendered.config | first-line) }
    } else {
      let r = ($rendered.config | ^talosctl validate --config /dev/stdin --mode metal --strict | complete)
      {
        node: $n
        result: (if $r.exit_code == 0 { $"(ansi green)✓ valid(ansi reset)" } else { $"(ansi red)✗ invalid(ansi reset)" })
        detail: (if $r.exit_code == 0 { "" } else { [$r.stderr $r.stdout] | str join "\n" | first-line })
      }
    }
  } | collect
}

# Pad a pending run of removals/additions to equal length and append it to the paired output.
# Pairing positionally is what makes a pure reordering line up across the two columns.
def flush-run []: record -> record {
  let acc = $in
  let n = ([($acc.dels | length) ($acc.adds | length)] | math max)
  let blank = { n: null, text: "", kind: null }
  {
    minus: ($acc.minus | append (0..<$n | each {|i| $acc.dels | get --optional $i | default $blank }))
    plus: ($acc.plus | append (0..<$n | each {|i| $acc.adds | get --optional $i | default $blank }))
    dels: []
    adds: []
    old: $acc.old
    new: $acc.new
  }
}

# Split a unified diff into aligned minus/plus columns. Context appears on both sides; a run of
# changes is padded on the shorter side and flushed at the next context line, which keeps runs
# aligned independently. Line numbers seed from the `@@` hunk header and advance per side — a
# removal only moves the old counter, an addition only the new one, context both.
def pair-runs []: string -> record<minus: list<any>, plus: list<any>> {
  $in
  | lines
  | reduce --fold { minus: [], plus: [], dels: [], adds: [], old: 0, new: 0 } {|line, acc|
    if (($line | str starts-with "--- ") or ($line | str starts-with "+++ ")) {
      $acc
    } else if ($line | str starts-with "@@") {
      let hunk = ($line | parse --regex '@@ -(?<old>\d+)(?:,\d+)? \+(?<new>\d+)' | get --optional 0)
      let flushed = ($acc | flush-run)
      if $hunk == null {
        $flushed
      } else {
        $flushed | update old ($hunk.old | into int) | update new ($hunk.new | into int)
      }
    } else {
      let text = ($line | str substring 1..)
      match ($line | str substring 0..<1) {
        "-" => { $acc | update dels ($acc.dels | append { n: $acc.old, text: $text, kind: "del" }) | update old ($acc.old + 1) }
        "+" => { $acc | update adds ($acc.adds | append { n: $acc.new, text: $text, kind: "add" }) | update new ($acc.new + 1) }
        _ => {
          let flushed = ($acc | flush-run)
          $flushed
          | update minus ($flushed.minus | append { n: $acc.old, text: $text, kind: "context" })
          | update plus ($flushed.plus | append { n: $acc.new, text: $text, kind: "context" })
          | update old ($acc.old + 1)
          | update new ($acc.new + 1)
        }
      }
    }
  }
  | flush-run
  | select minus plus
}

# Render a column as delta's side-by-side gutter: right-aligned line number, `│`, then the line,
# truncated to `budget`. Truncating rather than letting nu wrap the cell is what keeps one diff
# line on one visual line, and so keeps the two sides aligned. Padding lines show an empty gutter.
# Counting grapheme clusters keeps the cut off the middle of a multi-byte character.
def column [budget: int]: list<any> -> string {
  $in
  | each {|e|
    let num = (if $e.n == null { "    " } else { $e.n | into string | fill --alignment right --width 4 })
    let text = (
      if ($e.text | str length --grapheme-clusters) > $budget {
        $"($e.text | str substring --grapheme-clusters 0..<($budget - 1))…"
      } else {
        $e.text
      }
    )
    let colour = (
      match $e.kind {
        "del" => "red"
        "add" => "green"
        _ => "default_dimmed"
      }
    )
    $"(ansi default_dimmed)($num)│(ansi reset)(ansi $colour)($text)(ansi reset)"
  }
  | str join "\n"
}

# A node's dry-run config diff, as the raw unified-diff body. talosctl writes the dry-run summary
# and the diff to stderr, so both streams are captured and searched. The config is passed in rather
# than rendered here, so `apply` can dry-run and apply the same bytes from one render.
def dry-run-body [node: string, config: string, args: list<string>]: nothing -> string {
  let r = ($config | ^talosctl apply-config --nodes $node --file /dev/stdin ...$args --dry-run | complete)
  if $r.exit_code != 0 {
    error make { msg: $"talosctl apply-config failed: ($r.stderr | first-line)" }
  }
  [$r.stdout $r.stderr] | str join "\n" | split row "Config diff:" | get --optional 1 | default "" | str trim
}

# Width available to each diff column. Nu's table borders cost 14 columns across four columns; the
# two diff columns split what is left, minus the 5-column `NNNN│` gutter each one carries. 80 is
# nu's own default when there is no terminal.
def col-budget [targets: list<string>, width?: int]: nothing -> int {
  let total = (
    if $width != null {
      $width
    } else {
      let c = (term size | get columns)
      if $c < 40 { 80 } else { $c }
    }
  )
  let node_w = ([...($targets | each {|n| $n | str length }) 4] | math max)
  [((($total - 14 - $node_w) // 2) - 5) 20] | math max
}

# Count of changed lines in a unified-diff body. `--- a` / `+++ b` are the diff's own headers; a
# removed `---` document separator renders as `----`, which must still count.
def changed-lines []: string -> int {
  $in
  | lines
  | where {|l| ($l | str substring 0..<1) in ["+" "-"] }
  | where {|l| not (($l | str starts-with "--- ") or ($l | str starts-with "+++ ")) }
  | length
}

# One node's diff row, or null when it already matches. Prints the per-node header line either way.
def diff-row [node: string, config: string, args: list<string>, budget: int]: nothing -> any {
  let body = (dry-run-body $node $config $args)
  let changed = ($body | changed-lines)
  if $changed == 0 {
    print $"(ansi green)✓(ansi reset) ($node) matches its rendered config"
    return null
  }
  print $"(ansi yellow)⚠(ansi reset) ($node): ($changed) changed lines"
  let paired = ($body | pair-runs)
  { node: $node, "-": ($paired.minus | column $budget), "+": ($paired.plus | column $budget) }
}

# Diff each node's rendered config against what it is running — `apply` without the apply. With no
# argument every declared node is checked; nodes that already match report and take no table row. A
# node that cannot be reached or rendered takes an error row, so one down node still leaves a diff
# for the rest. `--width` sizes the cells only, so it has to be paired with the renderer to be
# useful: `talos diff --width 200 | table --width 200`.
export def diff [...nodes: string, --width: int]: nothing -> table<node: string, "-": string, "+": string> {
  let targets = (if ($nodes | is-empty) { node-names } else { $nodes })
  let budget = (col-budget $targets $width)
  let shared = (resolved-layers ($targets | any {|n| is-controlplane $n }))
  $targets
  | each {|n|
    try {
      diff-row $n (render $n $shared) [] $budget
    } catch {|e|
      print $"(ansi red)✗(ansi reset) ($n): ($e.msg | first-line)"
      { node: $n, "-": $"(ansi red)($e.msg | first-line)(ansi reset)", "+": "" }
    }
  }
  | compact
}

# Render a node's config. Routed through `bat`, which highlights on a terminal and passes bytes
# through unchanged when piped, so redirecting to a file still yields a usable config.
export def show [node: string]: nothing -> any {
  let config = (render $node)
  if (which bat | is-not-empty) {
    $config | ^bat --language yaml --style plain --paging never
  } else {
    $config
  }
}

# Show a node's dry-run diff in the same table `diff` renders, then apply it on confirmation. The
# config is rendered once and reused for the dry run and the apply, so one confirmation costs one
# `op inject` and one factory POST.
export def apply [node: string, ...args: string]: nothing -> nothing {
  let config = (render $node)
  let row = (diff-row $node $config $args (col-budget [$node]))
  if $row != null { print [$row] }
  if (confirm $"Apply above config to node ($node)?") {
    $config | ^talosctl apply-config --nodes $node --file /dev/stdin ...$args
  }
}

# Actions `lifecycle` accepts, for shell completion.
def lifecycle-actions []: nothing -> list<string> {
  ["upgrade" "reboot" "reset" "shutdown"]
}

# Upgrade, reboot, reset or shut down a node.
export def lifecycle [action: string@lifecycle-actions, node: string]: nothing -> nothing {
  match $action {
    "upgrade" => {
      let image = (machine-image $node)
      if (confirm $"Upgrade node ($node) with image ($image)?") {
        ^talosctl upgrade --nodes $node --image $image --reboot-mode powercycle --timeout=10m
      }
    }
    "reboot" => {
      if (confirm $"Reboot node ($node)?") { ^talosctl reboot --nodes $node --mode powercycle }
    }
    "reset" => {
      if (confirm $"Reset node ($node)?") { ^talosctl reset --nodes $node --graceful=false }
    }
    "shutdown" => {
      if (confirm $"Shutdown node ($node)?") { ^talosctl shutdown --nodes $node --force }
    }
    _ => {
      error make {
        msg: $"unknown action: ($action)"
        label: { text: $"one of: (lifecycle-actions | str join ', ')", span: (metadata $action).span }
      }
    }
  }
}

# Download a Talos ISO built from the current schematic. curl rather than `http get` for the retry,
# resume and remove-on-error handling a multi-hundred-megabyte download wants.
export def download-image [version: string]: nothing -> nothing {
  let id = (schematic-id)
  let output = $"($HERE)/talos-($version)-($id | str substring 0..<8)-metal-amd64.iso"
  let url = $"https://factory.talos.dev/image/($id)/($version)/metal-amd64.iso"
  ^gum spin --title $"Downloading Talos ($version) ..." -- curl --silent --fail --location --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors --output $output $url
}

# Upgrade the cluster's Kubernetes components via the first configured endpoint.
export def upgrade-k8s [version: string]: nothing -> nothing {
  let endpoint = (^talosctl config info --output yaml | from yaml | get endpoints.0)
  ^talosctl upgrade-k8s --nodes $endpoint --to $version
}
