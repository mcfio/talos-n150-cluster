---
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: {{ op://$VAULT/$SECRET_NAME/certificate-authority-data }}
    server: {{ op://$VAULT/$SECRET_NAME/server }}
  name: {{ op://$VAULT/$SECRET_NAME/cluster-name }}
contexts:
- context:
    cluster: {{ op://$VAULT/$SECRET_NAME/cluster-name }}
    namespace: default
    user: {{ op://$VAULT/$SECRET_NAME/username }}@{{ op://$VAULT/$SECRET_NAME/cluster-name }}
  name: {{ op://$VAULT/$SECRET_NAME/username }}@{{ op://$VAULT/$SECRET_NAME/cluster-name }}
current-context: {{ op://$VAULT/$SECRET_NAME/username }}@{{ op://$VAULT/$SECRET_NAME/cluster-name }}
kind: Config
preferences: {}
users:
- name: {{ op://$VAULT/$SECRET_NAME/username }}@{{ op://$VAULT/$SECRET_NAME/cluster-name }}
  user:
    client-certificate-data: {{ op://$VAULT/$SECRET_NAME/client-certificate-data }}
    client-key-data: {{ op://$VAULT/$SECRET_NAME/client-key-data }}
