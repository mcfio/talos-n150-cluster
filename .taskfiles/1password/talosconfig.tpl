context: {{ op://$VAULT/$SECRET_NAME/cluster-name }}
contexts:
    {{ op://$VAULT/$SECRET_NAME/cluster-name }}:
        ca: {{ op://$VAULT/$SECRET_NAME/talos/ca }}
        crt: {{ op://$VAULT/$SECRET_NAME/talos/crt }}
        key: {{ op://$VAULT/$SECRET_NAME/talos/key }}
