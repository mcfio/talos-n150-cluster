# Cluster Bootstrap

## Flux Installation

Presently, the cluster build automation handles provisiong and `bootstrapping` flux into a cluster by default an example can be found [here](https://github.com/mcfio/terraform-talos-cluster/tree/main).

```sh
kubectl apply --server-side --kustomize ./flux
```

## Secrets Configuration

_Normally_ encrypted manifefsts cannot be applied directly using `kubectl` and therefore must be decrypted locally prior to being applied.

```sh
sops --decrypt ./flux/age-key.enc.yaml | kubectl apply -f -
```

## Configure Flux

This command will apply the `gotk-sync.yaml` file and will apply the flux kustomizations.

```sh
kubectl apply --server-side --kustomize ../kubernetes/flux-system/
```
