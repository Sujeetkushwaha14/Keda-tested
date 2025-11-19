$RG="rg-exp-2566780-5699-storage"
$SA_NAME="stoexp25667805699"

# Storage Account ARM id
$SA_RES_ID = az storage account show -g $RG -n $SA_NAME --query id -o tsv

# Your user’s object id
$ME_OBJECTID = az ad signed-in-user show --query id -o tsv

# Assign contributor rights for queues
az role assignment create `
  --assignee-object-id $ME_OBJECTID `
  --role "Storage Queue Data Contributor" `
  --scope $SA_RES_ID
