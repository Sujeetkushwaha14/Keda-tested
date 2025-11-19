$AKS_NS="keda-ns"    

kubectl get scaledobject -n $AKS_NS
kubectl describe scaledobject nginx-queue-scaledobject -n $AKS_NS

kubectl get deploy/nginx-queue-scale -n $AKS_NS -w

# kubectl get hpa -n $AKS_NS -w
