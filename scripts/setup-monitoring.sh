#!/bin/bash
set -euo pipefail

# Configurable variables (can be overridden via env vars)
HELM_RELEASE="${HELM_RELEASE:-kube-monitoring}"
NAMESPACE="${NAMESPACE:-monitoring}"
VALUES_FILE="${VALUES_FILE:-helm-values/prometheus-grafana/values.yaml}"
DASHBOARD_DIR="${DASHBOARD_DIR:-helm-values/grafana/dashboards}"

usage() {
  echo "Usage: $0 [install|upgrade|dashboards|help]"
  echo "  install     Install kube-prometheus-stack"
  echo "  upgrade     Upgrade kube-prometheus-stack"
  echo "  dashboards  Update Grafana dashboards from JSON files"
  echo "  help        Show this help message"
  exit 1
}

# Check prerequisites
check_prerequisites() {
  echo "🔍 Checking prerequisites..."
  command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required but not installed."; exit 1; }
  command -v helm >/dev/null 2>&1 || { echo "❌ helm is required but not installed."; exit 1; }
  if [ ! -f "$VALUES_FILE" ]; then
    echo "❌ Values file '$VALUES_FILE' not found."
    exit 1
  fi
}

ensure_metrics_server() {
  echo "📈 Ensuring Metrics Server is installed..."
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

  # Only patch for Docker Desktop if needed
  if kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}' | grep -q docker; then
    echo "🔧 Patching metrics-server for Docker Desktop..."
    kubectl patch deployment metrics-server -n kube-system \
      --type=json \
      -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' || {
      echo "⚠️ Failed to patch metrics-server, continuing...";
    }
  fi
}

install_stack() {
  echo "🚀 Installing kube-prometheus-stack..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || {
    echo "⚠️ Failed to add Helm repo, continuing...";
  }
  helm repo update

  # Install kube-prometheus-stack
  helm install "$HELM_RELEASE" prometheus-community/kube-prometheus-stack \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f "$VALUES_FILE" \
    --version 61.7.0 || { echo "❌ Failed to install kube-prometheus-stack."; exit 1; }
}

upgrade_stack() {
  echo "🔄 Upgrading kube-prometheus-stack..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || {
    echo "⚠️ Failed to add Helm repo, continuing...";
  }
  helm repo update

  # Upgrade kube-prometheus-stack
  helm upgrade "$HELM_RELEASE" prometheus-community/kube-prometheus-stack \
    --namespace "$NAMESPACE" \
    -f "$VALUES_FILE" \
    --version 61.7.0 || { echo "❌ Failed to upgrade kube-prometheus-stack."; exit 1; }
}

update_dashboards() {
  echo "📊 Updating Grafana dashboards from: $DASHBOARD_DIR"

  if [ ! -d "$DASHBOARD_DIR" ]; then
    echo "❌ Dashboard directory '$DASHBOARD_DIR' not found."
    exit 1
  fi

  # Create or update ConfigMap for dashboards
  echo "📁 Creating/updating Grafana dashboard ConfigMap..."
  kubectl create configmap grafana-dashboards \
    --from-file="$DASHBOARD_DIR" \
    --namespace "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f - || {
      echo "❌ Failed to create/update dashboard ConfigMap.";
      exit 1;
    }

  # Label ConfigMap for Grafana sidecar
  kubectl label configmap grafana-dashboards grafana_dashboard=1 -n "$NAMESPACE" --overwrite || {
    echo "❌ Failed to label dashboard ConfigMap.";
    exit 1;
  }

  # Reload dashboards without restarting Grafana (if sidecar is configured)
  echo "ℹ️ Dashboards will be reloaded by Grafana sidecar (ensure sidecar is enabled in values.yaml)."
}

show_status() {
  echo
  echo "🔐 Grafana admin password:"
  if kubectl get secret "$HELM_RELEASE-grafana" -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl get secret "$HELM_RELEASE-grafana" -n "$NAMESPACE" -o jsonpath="{.data.admin-password}" | base64 -d 2>/dev/null || echo "⚠️ Failed to decode password."
  else
    echo "⚠️ Grafana secret not found."
  fi
  echo

  echo "📊 Prometheus pod usage:"
  kubectl top pods -n "$NAMESPACE" 2>/dev/null | grep prometheus || echo "⚠️ Prometheus pods not found or metrics-server not ready."

  echo
  echo "📊 Grafana pod usage:"
  kubectl top pods -n "$NAMESPACE" 2>/dev/null | grep grafana || echo "⚠️ Grafana pods not found or metrics-server not ready."

  echo
  echo "🔧 Metrics server args:"
  if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    kubectl get deployment metrics-server -n kube-system -o=jsonpath="{.spec.template.spec.containers[0].args}" 2>/dev/null || echo "⚠️ Metrics server not found."
  else
    echo "⚠️ Metrics server not found."
  fi
  echo
}

# === Main ===
if [ $# -ne 1 ]; then usage; fi

check_prerequisites

case "$1" in
  install)
    install_stack
    ensure_metrics_server
    show_status
    ;;
  upgrade)
    upgrade_stack
    show_status
    ;;
  dashboards)
    update_dashboards
    show_status
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    echo "❌ Unknown command: $1"
    usage
    ;;
esac