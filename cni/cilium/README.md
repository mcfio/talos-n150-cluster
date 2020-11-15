# Cilium CNI configuration for the cluster

Presently, manually installed using helm

```bash
helm install cilium cilium/cilium \
  --version 1.9.0 \
  --namespace kube-system \
  -f ./values-1.9.0.yaml
```

*Note* - Cilium does not yet support multi-arch images, and arm64 images are pushed to the `-dev` image repo. The helm template still has a bug when using the dev images
for the cilium operator and a patch is required to modify the image name

```bash
kubectl -n kube-system patch deployments.apps cilium-operator --patch '{"spec": {"template": {"spec": {"containers": [{"name": "cilium-operator","image": "cilium/operator-dev:v1.9.0"}]}}}}
```
