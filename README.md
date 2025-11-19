# KEDA-Testing
kubectl get hpa -n keda-ns -w
kubectl get deploy/nginx-queue-scale -n keda-ns -w

# 0) Prereqs you already have

* AKS cluster (you’re logged in with `kubectl` context set)
* Azure Storage Account + a Queue created
* Your Azure subscription user has RBAC to create identities & role assignments

---

# 1) One-time Azure setup (PowerShell-friendly `az` CLI)

> You can paste this whole block into PowerShell; it uses variables so you only edit the first few lines.

```powershell
# ==== EDIT THESE ====
$SUBSCRIPTION="<your-subscription-id>"
$RG="<your-resource-group>"
$AKS_NAME="<your-aks-name>"
$AKS_NS="workload-demo"            # k8s namespace to use
$SA_NAME="<yourstorageacctname>"   # storage account name (no connection string needed)
$QUEUE_NAME="<your-queue-name>"
$UAMI_NAME="keda-queue-uami"       # user-assigned managed identity name
$LOCATION="<your-azure-region>"    # e.g. westeurope
$SA_CLIENTID_ANNOT="1c835a58-5884-4d0a-86fe-1e8a813f47df"              # we'll fill after we create identity
$SA_NAME_K8S="keda-queue-sa"       # k8s service account name used by the scaled workload
# =====================
az storage message peek --queue-name demo-queue --account-name stoexp25667805699 --auth-mode login


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
$SUBJECT="system:serviceaccount:$AKS_NS:$SA_NAME_K8S"

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
```

**Why this matters:** KEDA uses the ServiceAccount’s federated token to get an AAD token as the UAMI and call Storage Queue APIs. No connection strings involved. ([Microsoft Learn][1], [KEDA][2])

---

# 2) Install KEDA on AKS (Helm)

```powershell
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
# Install KEDA into its own namespace with Workload Identity support
helm install keda kedacore/keda --namespace keda --create-namespace `
  --set podIdentity.azureWorkload.enabled=true
```

> KEDA 2.x supports the **azure-workload** identity provider; enabling WI at install is recommended. ([KEDA][2])

---

# 3) Kubernetes YAML (save as files and apply)

> Replace placeholders (`<...>`) or let the variables above guide your values.

### 3.1 `00-namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: workload-demo
```

### 3.2 `01-serviceaccount.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: keda-queue-sa
  namespace: workload-demo
  annotations:
    azure.workload.identity/use: "true"
    # Client ID of the User Assigned Managed Identity created above
    azure.workload.identity/client-id: "<UAMI_CLIENT_ID>"
```

### 3.3 `02-deployment-nginx.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-queue-scale
  namespace: workload-demo
spec:
  replicas: 0
  selector:
    matchLabels:
      app: nginx-queue-scale
  template:
    metadata:
      labels:
        app: nginx-queue-scale
    spec:
      serviceAccountName: keda-queue-sa
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        # nginx is just a placeholder workload to observe scale-out
```

### 3.4 `03-triggerauth.yaml`

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: azqueue-auth-wi
  namespace: workload-demo
spec:
  podIdentity:
    provider: azure-workload
    # Explicitly tell KEDA which UAMI to use (clientId).
    # This is optional if you rely purely on the SA annotation, but recommended for clarity.
    identityId: "<UAMI_CLIENT_ID>"
```

### 3.5 `04-scaledobject.yaml`

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: nginx-queue-scaledobject
  namespace: workload-demo
spec:
  scaleTargetRef:
    name: nginx-queue-scale
  pollingInterval: 5            # seconds between checks
  cooldownPeriod: 30            # scale down grace
  minReplicaCount: 0
  maxReplicaCount: 10
  triggers:
  - type: azure-queue
    metadata:
      accountName: "<STORAGE_ACCOUNT_NAME>"
      queueName: "<QUEUE_NAME>"
      # scale up 1 pod per this many messages
      queueLength: "5"
      # optional: don't wake up until there are at least this many
      activationQueueLength: "1"
      cloud: "AzurePublicCloud"
    authenticationRef:
      name: azqueue-auth-wi
```

> `azure-queue` supports `accountName` + Workload Identity (no connection string). `TriggerAuthentication` with `provider: azure-workload` + SA annotations makes it work. ([KEDA][3])

**Apply all YAML:**

```powershell
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-serviceaccount.yaml
kubectl apply -f 02-deployment-nginx.yaml
kubectl apply -f 03-triggerauth.yaml
kubectl apply -f 04-scaledobject.yaml
```

---

# 4) End-to-end test (no connection strings)

## 4.1 Put some messages into the queue

Use your own identity (Azure RBAC) to enqueue messages:

```powershell
# Put 50 messages (adjust as you like)
1..50 | ForEach-Object {
  az storage message put `
    --queue-name $QUEUE_NAME `
    --account-name $SA_NAME `
    --content "test-$_" `
    --auth-mode login | Out-Null
}
```

> `--auth-mode login` uses your AAD creds rather than a connection string. ([KEDA][3])

## 4.2 Watch KEDA scale your nginx Deployment

```powershell
kubectl get scaledobject -n $AKS_NS
kubectl describe scaledobject nginx-queue-scaledobject -n $AKS_NS

# Watch pods appear
kubectl get deploy/nginx-queue-scale -n $AKS_NS -w

# (Optional) also watch the generated HPA
kubectl get hpa -n $AKS_NS -w
```

* As messages pile up beyond `queueLength`, replicas should grow (e.g., 50 messages with `queueLength: 5` → \~10 replicas).

## 4.3 (Optional) Clear messages and watch scale down

```powershell
# Dequeue messages quickly (simulate a consumer deleting messages).
# Here we simply clear the queue (for testing only):
az storage queue clear --name $QUEUE_NAME --account-name $SA_NAME --auth-mode login

# Within ~cooldownPeriod seconds, replicas should drop back toward minReplicaCount.
```

---

# 5) Troubleshooting quick hits

* **Pods stay at 0 replicas:**

  * Check identity binding: `kubectl describe sa keda-queue-sa -n workload-demo` (ensure annotations contain your UAMI clientId).
  * Verify the federated credential subject exactly matches `system:serviceaccount:workload-demo:keda-queue-sa`.
  * Confirm the UAMI has **Storage Queue Data Reader** (or Contributor) on the Storage Account scope.
  * Look at KEDA operator logs: `kubectl logs -n keda deploy/keda-operator` (errors usually mention auth).
    References: KEDA WI auth & scaler docs. ([KEDA][2])

* **Queue exists but scaler says it can’t read length:**

  * Double-check `$SA_NAME`, `$QUEUE_NAME`, and region/tenant.
  * Ensure AKS has **OIDC issuer** and **Workload Identity** enabled. ([Microsoft Learn][1])

---

# 6) Cleanup

```powershell
kubectl delete namespace workload-demo
helm uninstall keda -n keda
az identity delete -g $RG -n $UAMI_NAME
```

---

## Notes & References

* **KEDA Azure Storage Queue scaler** parameters & examples. ([KEDA][3])
* **Azure AD Workload Identity** with KEDA (`azure-workload` provider) and overriding identity via `identityId`. ([KEDA][2])
* **AKS + KEDA + Workload Identity** guidance from Microsoft Docs. ([Microsoft Learn][1])


[1]: https://learn.microsoft.com/en-us/azure/aks/keda-workload-identity?utm_source=chatgpt.com "Securely scale your applications using the KEDA add-on ..."
[2]: https://keda.sh/docs/2.17/authentication-providers/azure-ad-workload-identity/?utm_source=chatgpt.com "Azure AD Workload Identity"
[3]: https://keda.sh/docs/2.17/scalers/azure-storage-queue/?utm_source=chatgpt.com "Azure Storage Queue"
