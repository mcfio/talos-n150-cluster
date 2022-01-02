# Bootstrapping the cluster for GitOps management of deployments

```bash
flux install \
  --version=latest \
  --network-policy=false \
  --export > ./flux-components.yaml
```

## Apply the flux-components manifest

```bash
kubectl apply -f ./flux-components.yaml
```

## Apply the repo sync configuration

```bash
kubectl apply -f ./git-repository.yaml
kubectl apply -f ./flux-system.yaml
```
