$KEDA_NS          = "keda"
$KEDA_SA          = "keda-operator"
$SUBSCRIPTION     = "6dbc33a2-5da4-4090-8ac2-b8dde7d2a834"
$RG               = "Rg1"
$AKS_NAME         = "kedaAksCluster"
$UAMI_NAME        = "keda-queue-uami"


az account set -s $SUBSCRIPTION

# Get OIDC issuer & UAMI client ID
$OIDC_ISSUER = az aks show -g $RG -n $AKS_NAME --query "oidcIssuerProfile.issuerUrl" -o tsv
$UAMI_CLIENT = az identity show -g $RG -n $UAMI_NAME --query clientId -o tsv

# Create federated credential for the operator service account
$SUBJECT = "system:serviceaccount:${KEDA_NS}:${KEDA_SA}"
az identity federated-credential create `
  --name "keda-operator-wi" `
  --identity-name $UAMI_NAME `
  --resource-group $RG `
  --issuer $OIDC_ISSUER `
  --subject $SUBJECT `
  --audience "api://AzureADTokenExchange"

# Annotate the operator ServiceAccount with the UAMI clientId
kubectl annotate sa $KEDA_SA -n $KEDA_NS azure.workload.identity/use="true" --overwrite
kubectl annotate sa $KEDA_SA -n $KEDA_NS azure.workload.identity/client-id="$UAMI_CLIENT" --overwrite

# Restart operator so it picks up the annotation
kubectl rollout restart deploy/keda-operator -n $KEDA_NS
