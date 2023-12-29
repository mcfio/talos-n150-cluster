---
apiVersion: v1
kind: Config
preferences: {}
current-context: {{ op://$VAULT/$SECRET_NAME/username }}@{{ op://$VAULT/$SECRET_NAME/cluster-name }}
clusters:
  - name: {{ op://$VAULT/$SECRET_NAME/cluster-name }}
    cluster:
      certificate-authority-data: {{ op://$VAULT/$SECRET_NAME/certificate-authority-data }}
      server: {{ op://$VAULT/$SECRET_NAME/server }}
contexts:
  - name: {{ op://$VAULT/$SECRET_NAME/username }}@{{ op://$VAULT/$SECRET_NAME/cluster-name }}
    context:
      cluster: {{ op://$VAULT/$SECRET_NAME/cluster-name }}
      namespace: default
      user: {{ op://$VAULT/$SECRET_NAME/username }}@{{ op://$VAULT/$SECRET_NAME/cluster-name }}
users:
  - name: {{ op://$VAULT/$SECRET_NAME/username }}@{{ op://$VAULT/$SECRET_NAME/cluster-name }}
    user:
      client-certificate-data: {{ op://$VAULT/$SECRET_NAME/client-certificate-data }}
      client-key-data: {{ op://$VAULT/$SECRET_NAME/client-key-data }}
