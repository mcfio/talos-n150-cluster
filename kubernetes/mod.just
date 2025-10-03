set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

requested := "reconcile.fluxcd.io/requestedAt=$(date +%s)"
forced := "reconcile.fluxcd.io/forcedAt=$(date +s)"

[private]
default:
    just --list kubernetes --unsorted

[doc('Open a shell on a node')]
shell node:
    kubectl node-shell --namespace kube-system --image mirror.gcr.io/alpine:latest -x {{ node }}

[doc('Browse a PVC')]
browse-pvc namespace claim:
    kubectl browse-pvc --namespace {{ namespace }} -i mirror.gcr.io/alpine:latest {{ claim }}

[doc('View a secret')]
view-secret namespace *args:
    kubectl view-secret --namespace {{ namespace }} {{ args }}

[doc('Snapshot VolSync PVCs')]
snapshot:
    kubectl get replicationsources --no-headers --all-namespaces | while read -r namespace name _; do \
        kubectl --namespace "$namespace" patch replicationsources "$name" --type merge --patch '{"spec":{"trigger":{"manual":"$(date +%s)"}}}'; \
    done

[doc('Suspend or resume VolSync')]
volsync state:
    flux -n volsync-system {{ state }} kustomization volsync
    flux -n volsync-system {{ state }} helmrelease volsync
    kubectl --namespace volsync-system scale deployment volsync --replicas {{ if state != "suspend" { "1" } else { "0" } }}

[doc('Sync ExternalSecrets')]
sync-es:
    kubectl get externalsecrets.external-secrets.io --no-headers --all-namespaces | while read -r namespace resource _; do \
        kubectl --namespace "$namespace" annotate --field-manager flux-client-side-apply \
          --overwrite externalsecrets.external-secrets.io "$resource" force-sync="$(date +%s)"; \
    done

[doc('Sync HelmReleases')]
sync-hr:
    kubectl get helmreleases.helm.toolkit.fluxcd.io --no-headers --all-namespaces | while read -r namespace resource _; do \
        kubectl --namespace "$namespace" annotate --field-manager flux-client-side-apply \
          --overwrite HelmReleases.helm.toolkit.fluxcd.io "$resource" {{ requested }} {{ forced }}; \
    done

[doc('Sync Kustomizations')]
sync-ks:
    kubectl get kustomizations.kustomize.toolkit.fluxcd.io --no-headers --all-namespaces | while read -r namespace resource _; do \
        kubectl --namespace "$namespace" annotate --field-manager flux-client-side-apply \
          --overwrite kustomizations.kustomize.toolkit.fluxcd.io "$resource" {{ requested }}; \
    done

[doc('Sync OCIRepositories')]
sync-oci:
    kubectl get ocirepositories.source.toolkit.fluxcd.io --no-headers --all-namespaces | while read -r namespace resource _; do \
        kubectl --namespace "$namespace" annotate --field-manager flux-client-side-apply \
          --overwrite ocirepositories.source.toolkit.fluxcd.io "$resource" {{ requested }}; \
    done

[doc('Clean-up pods in Failed or Succeeded state')]
cleanup:
    for phase in Failed Succeeded; do \
        kubectl delete pods --all-namespaces --field-selector status.phase="$phase" --ignore-not-found=true; \
    done

