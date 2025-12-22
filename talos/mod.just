set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

talos_dir := justfile_directory() + '/talos'
controller := `talosctl config info -o yaml | yq -e '.endpoints[0]'`

[private]
default:
    just --list talos --unsorted

[doc('Render Talos config for a node')]
render-config node:
    talosctl machineconfig patch <(just talos::template {{ node }}) \
        --patch @{{ talos_dir }}/nodes/{{ node }}.yaml

[doc('Apply Talos config to a node')]
apply-config node *args:
    just talos::render-config "{{ node }}" | talosctl apply-config --nodes "{{ node }}" --file /dev/stdin {{ args }}

[doc('Upgrade Kubernetes version on the cluster')]
upgrade-k8s version:
    talosctl upgrade-k8s --nodes "{{ controller }}" --to {{ version }}

[doc('Download Talos machine image')]
download-image version schematic:
    gum spin --title "Downloading Talos {{ version }} ..." -- \
    curl -sfL --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors \
        --output "{{ talos_dir }}/talos-{{ version }}-{{ replace_regex(schematic, '^(.{8}).*', '$1') }}.iso" \
        "https://factory.talos.dev/image/{{ schematic }}/{{ version }}/metal-amd64.iso"
    just log info "Downloaded Talos" version "{{ version }}" schematic "{{ schematic }}"

[doc('Upgrade Talos on a node')]
[group('node lifecycle')]
upgrade node:
    gum confirm "Upgrade node {{ node }} with image $(just talos::machine-image {{ node }})" --default=No && \
        talosctl upgrade --nodes "$(just talos::machine-ip {{ node }})" --image "$(just talos::machine-image {{ node }})" --reboot-mode powercycle --timeout=10m

[doc('Reboot a Talos node')]
[group('node lifecycle')]
reboot node:
    gum confirm "Reboot node {{ node }}?" --default=No && \
        talosctl reboot --nodes {{ node }} --mode powercycle --dry-run || exit 0

[doc('Reset a Talos node')]
[group('node lifecycle')]
reset node:
    gum confirm "Reset node {{ node }}?" --default=No && \
        talosctl reset --nodes "{{ node }}" --graceful=false || exit 0

[doc('Shutdown a Talos node')]
[group('node lifecycle')]
shutdown node:
    gum confirm "Shutdown node {{ node }}?" --default=No && \
        talosctl shutdown --nodes "{{ node }}" --force || exit 0

[private]
template node:
    minijinja-cli --define "is_controlplane:=$(just talos is_controlplane {{ node }})" \
      {{ talos_dir }}/machineconfig.yaml.j2 | op inject

[private]
is_controlplane node:
    yq 'select(.machine) | (.machine.type == "controlplane")' {{ talos_dir }}/nodes/{{ node }}.yaml

[private]
machine-ip node:
    kubectl get nodes {{ node }} --output jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'

[private]
machine-image node:
    yq 'select(.machine) | .machine.install.image' "{{ talos_dir }}/nodes/{{ node }}.yaml"

[private]
gen-schematic-id +type='metal':
    curl --silent -X POST --data-binary \
        "@{{ talos_dir }}/schematics/{{ type }}.yaml" "https://factory.talos.dev/schematics" | jq --raw-output '.id'
