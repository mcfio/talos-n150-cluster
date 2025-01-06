---
apiVersion: v1
kind: Namespace
metadata:
  name: external-secrets
---
apiVersion: v1
kind: Secret
metadata:
  name: onepassword-connect-secret
  namespace: external-secrets
stringData:
  1password-credentials.json: {{ op://mcfio-home-cluster/onepassword-connect/CREDENTIAL }}
  token: {{ op://mcfio-home-cluster/onepassword-connect/TOKEN }}
