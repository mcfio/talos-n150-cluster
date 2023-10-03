# Cluster Bootstrap

## Flux Installation

```sh
kubectl apply --server-side --kustomize ./flux
```

## Secrets Configuration

_Normally_ encrypted manifefsts cannot be applied directly using `kubectl` and must be decrypted locally prior to being applied to the cluster.

```sh
sops --decrypt ./flux/age-key.enc.yaml | kubectl apply -f -
sops --decrypt ./flux/github-deploy-key.enc.yaml | kubectl apply -f -
```

## Configure Flux

```sh
kubectl apply --server-side --kustomize ../flux/config
```
