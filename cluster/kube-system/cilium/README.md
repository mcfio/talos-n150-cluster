# Cilium CNI

This cluster intends to be kube-proxy free, Cilium provides a generic installation guide found [here](https://docs.cilium.io/en/v1.10/gettingstarted/kubeproxy-free/#kubeproxy-free) - Therefor
for Aarch64 platforms (like this cluster) a few modifications are required and detailed in the helm `values.yaml` file.

This configuration enables [Direct Server Return](https://docs.cilium.io/en/v1.10/gettingstarted/kubeproxy-free/#dsr-mode) (DSR), this requires Native-Routing and will preserve the client source IP address.

Setup Helm repository:

```bash
helm repo add cilium https://helm.cilium.io/
```

Deploy Cilium release via helm:

```bash
helm install cilium cilium/cilium \
  --version $VERSION \
  --namespace kube-system \
  -f ./helm-values.yaml
```
