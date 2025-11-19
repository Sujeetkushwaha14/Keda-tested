$RG="sujeetrg"
$SA_NAME="kedastoragesujeet"

# Storage Account ARM id
$SA_RES_ID = az storage account show -g $RG -n $SA_NAME --query id -o tsv

# Your user’s object id
$ME_OBJECTID = az ad signed-in-user show --query id -o tsv

# Assign contributor rights for queues
az role assignment create `
  --assignee-object-id $ME_OBJECTID `
  --role "Storage Queue Data Contributor" `
  --scope $SA_RES_ID

# az role assignment create `
#   --assignee a4f9107a-edea-4c43-9d29-efa86e789753 `
#   --role "Storage Queue Data Contributor" `
#   --scope /subscriptions/6dbc33a2-5da4-4090-8ac2-b8dde7d2a834/resourceGroups/sujeetrg/providers/Microsoft.Storage/storageAccounts/kedastoragesujeet
