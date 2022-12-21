# Cluster Bootstrap

## Flux Installation

```sh
kubectl apply --server-side --kustomize ./flux
```

## Secrets Configuration

_Normally these cannot be applied directly using `kubectl`_

```sh
sops --decrypt ./flux/age-key.enc.yaml | kubectl apply -f -
sops --decrypt ./flux/github-deploy-key.enc.yaml | kubectl apply -f -
```

## Configure Flux

```sh
kubectl apply --server-side --kustomize ../flux/config
```
