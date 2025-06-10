kubectl delete secret cluster-regcred -n kube-system
kubectl create secret docker-registry cluster-regcred \
  --docker-server=<new-server> \
  --docker-username=<new-user> \
  --docker-password=<new-password> \
  --docker-email=<new-email> \
  --namespace=kube-system

# For Docker Hub, use --docker-server=https://index.docker.io/v1/ if needed.

kubectl get pod <pod-name> -o yaml | grep imagePullSecrets  # Should show the secret
kubectl describe secret cluster-regcred -n kube-system  # Check if credentials are valid