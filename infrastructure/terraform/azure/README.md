# Terraform configuration for Pi4-Cluster in Azure AD

## Create necessary Azure AD permissions for use with Terraform Cloud

Create necessay RBAC application registration, this service principal (sp) becomes the owner of any other resources or sp created through terraform.

Because our user will be creating service principals within our subscription requires additional API permissions

```bash
tenantId=$(az account show -o json | jq -r '.tenantId')
subscriptionId=$(az account show -o json | jq -r '.id')

appId=$(az ad sp create-for-rbac --name "terraform-cloud-sp" --role="Contributor" --scopes="/subscriptions/$subscriptionId" --query appId -o tsv)
clientSecret=$(az ad app credential reset --id $appId --query password -o tsv)
```

Make note of the application ID and the password, the password is only shown once.

```bash
# Microsoft Graph API
API_Microsoft_Graph="00000003-0000-0000-c000-000000000000"

# Application.ReadWrite.OwnedBy
PERMISSION_MG_Application_ReadWrite_OwnedBy="18a4783c-866b-4cc7-a460-3d5e5662c884"

az ad app permission add --id $appId --api $API_Microsoft_Graph --api-permissions $PERMISSION_MG_Application_ReadWrite_OwnedBy=Role

az ad app permission grant --id $appId --api $API_Microsoft_Graph --scope $PERMISSION_MG_Application_ReadWrite_OwnedBy

az ad app permission admin-consent --id $appId
```

The following are to be defined as terraform cloud variables

```env
ARM_CLIENT_ID=$appId
ARM_CLIENT_SECRET=$clientSecret
ARM_SUBSCRIPTION_ID=$subscriptionId
ARM_TENANT_ID=$tenantId
```

### TODO

- [ ] Refactor this to be a part of the bootstrap process
- [ ] Narrow the RBAC scope to be least priviledged
