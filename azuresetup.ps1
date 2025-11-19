$SUBSCRIPTION="6dbc33a2-5da4-4090-8ac2-b8dde7d2a834"
$RG="rg1"
$AKS_NAME="kedaAksCluster"
$AKS_NS="keda"            # k8s namespace to use
$SA_NAME="likuhanvinbeni"   # storage account name (no connection string needed)
$QUEUE_NAME="demo-queue"
$UAMI_NAME="keda-queue-uami"       # user-assigned managed identity name
$LOCATION="eastus"    # e.g. westeurope
$SA_CLIENTID_ANNOT="b3587135-0c44-493c-a882-3e51e127a3dc"              # we'll fill after we create identity
$SA_NAME_K8S="keda-queue-sa"       # k8s service account name used by the scaled workload

az account set -s $SUBSCRIPTION

# Make sure OIDC + Workload Identity are enabled on the AKS cluster
az aks update -g $RG -n $AKS_NAME --enable-oidc-issuer --enable-workload-identity

# Get the OIDC issuer URL (used for the federated credential)
$OIDC_ISSUER = az aks show -g $RG -n $AKS_NAME --query "oidcIssuerProfile.issuerUrl" -o tsv

# Create a user-assigned managed identity for KEDA to use when checking queue length
az identity create -g $RG -n $UAMI_NAME -l $LOCATION
$UAMI_ID      = az identity show -g $RG -n $UAMI_NAME --query id -o tsv
$UAMI_CLIENT  = az identity show -g $RG -n $UAMI_NAME --query clientId -o tsv
$UAMI_TENANT  = az identity show -g $RG -n $UAMI_NAME --query tenantId -o tsv

# Give the identity permission to read queue length (and optionally process messages)
# For KEDA’s scaler, "Storage Queue Data Reader" is enough; for a real worker, use "Storage Queue Data Contributor".
$SA_RES_ID = az storage account show -g $RG -n $SA_NAME --query id -o tsv
az role assignment create --assignee-object-id $(az identity show -g $RG -n $UAMI_NAME --query principalId -o tsv) `
  --role "Storage Queue Data Reader" --scope $SA_RES_ID

# Create the federated identity credential that lets the k8s ServiceAccount assume the UAMI
# The subject must match: system:serviceaccount:<namespace>:<serviceaccount-name>
$SUBJECT="system:serviceaccount:${AKS_NS}:${SA_NAME_K8S}"

az identity federated-credential create `
  --name "keda-queue-federation" `
  --identity-name $UAMI_NAME `
  --resource-group $RG `
  --issuer $OIDC_ISSUER `
  --subject $SUBJECT `
  --audience "api://AzureADTokenExchange"

# Save the clientId for the k8s ServiceAccount annotation step
$SA_CLIENTID_ANNOT = $UAMI_CLIENT
Write-Host "Managed Identity clientId: $SA_CLIENTID_ANNOT"
