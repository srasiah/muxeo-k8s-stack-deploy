#!/bin/bash

# Script to install or uninstall NGINX Ingress Controller
# Supports official manifest-based deployment

VERSION="v1.11.7"
NAMESPACE="ingress-nginx"
MANIFEST_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-$VERSION/deploy/static/provider/cloud/deploy.yaml"

usage() {
  echo ""
  echo "Usage: $0 [install|uninstall]"
  echo ""
  echo "Commands:"
  echo "  install     Install NGINX Ingress Controller"
  echo "  uninstall   Uninstall NGINX Ingress Controller"
  echo ""
  exit 1
}

install_ingress() {
  echo "📦 Installing NGINX Ingress Controller (version $VERSION)..."
  kubectl apply -f "$MANIFEST_URL"

  echo "⏳ Waiting for ingress controller pod to be ready..."
  kubectl wait --namespace "$NAMESPACE" \
    --for=condition=Ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=180s

  echo "✅ Installation complete!"
  kubectl get svc -n "$NAMESPACE"
}

uninstall_ingress() {
  echo "🗑️  Uninstalling NGINX Ingress Controller..."
  kubectl delete -f "$MANIFEST_URL"
  echo "✅ Uninstall complete!"
}

uninstall__clean_ingress() {
  echo "🗑️  Uninstalling NGINX Ingress Controller..."

  # Delete the resources (even if manifest has changed)
  echo "🔄 Deleting namespace '$NAMESPACE'..."
  kubectl delete namespace "$NAMESPACE" --ignore-not-found

  # Optional cleanup of leftover CRDs and webhooks
  echo "🧹 Cleaning up validating webhooks and CRDs..."
  kubectl delete validatingwebhookconfigurations.admissionregistration.k8s.io ingress-nginx-admission --ignore-not-found
  kubectl delete mutatingwebhookconfigurations.admissionregistration.k8s.io ingress-nginx-admission --ignore-not-found
  kubectl delete customresourcedefinitions.apiextensions.k8s.io -l app.kubernetes.io/name=ingress-nginx --ignore-not-found

  echo "✅ Uninstall complete!"
}


# Main
if [ $# -ne 1 ]; then
  usage
fi

case "$1" in
  install)
    install_ingress
    ;;
  uninstall)
    uninstall_ingress
    ;;
  *)
    usage
    ;;
esac
