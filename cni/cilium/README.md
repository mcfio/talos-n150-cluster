# Cilium CNI

This cluster intends to be kube-proxy free, Cilium provides a generic installation guide found [here](https://docs.cilium.io/en/v1.9/gettingstarted/kubeproxy-free/#kubeproxy-free) - Therefor for Aarch64 platforms (like this cluster) a few modifications are required and detailed in the helm `values.yaml` file.

This configuration enables [Direct Server Return](https://docs.cilium.io/en/v1.9/gettingstarted/kubeproxy-free/#dsr-mode) (DSR), this requires Native-Routing and will preserve the client source IP address.

Setup Helm repository:

```bash
helm repo add cilium https://helm.cilium.io/
```

Deploy Cilium release via helm:

```bash
helm install cilium cilium/cilium \
  --version 1.9.1 \
  --namespace kube-system \
  -f ./values-1.9.1.yaml
```

*Note* - Cilium does not yet fully support multi-arch images, and arm64 images are pushed to the `-dev` image repo. The helm template still has a bug when using the `-dev` images with cilium operator; a patch to the deployment is required that modifies the image name:

```bash
kubectl -n kube-system patch deployments.apps cilium-operator --patch '{"spec": {"template": {"spec": {"containers": [{"name": "cilium-operator","image": "cilium/operator-dev:v1.9.1"}]}}}}'
```

This issue is tracked here; [13829](https://github.com/cilium/cilium/issues/13829)
