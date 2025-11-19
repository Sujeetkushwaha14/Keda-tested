kubectl delete -f 1.serviceaccount.yaml --ignore-not-found
kubectl delete -f 2.deployment.yaml --ignore-not-found
kubectl delete -f 3.triggerauth.yaml --ignore-not-found
kubectl delete -f 4.scaledobject.yaml --ignore-not-found
Write-Output "Cluster resources removed."

