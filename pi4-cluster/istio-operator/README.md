# Istio Operator Install

```bash
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.7.3 sh -
```

```bash
helm template manifests/charts/istio-operator/ \
  --set hub=docker.io/querycapistio \
  --set tag=1.7.3 \
  --set operatorNamespace=istio-operator \
  --set istioNamespace=istio-system > ./operator.yaml
```

Note: We use the `docker.io/querycapistio` images as they are built multi-arch and provide manfiests for arm64.
