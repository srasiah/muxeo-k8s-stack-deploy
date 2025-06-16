#!/bin/bash
set -euo pipefail

HELM_RELEASE="kube-monitoring"
NAMESPACE="monitoring"
VALUES_FILE="helm-values/prometheus-grafana/values.yaml"
DASHBOARD_DIR="helm-values/grafana/dashboards"
KAFKA_SERVER="PLAINTEXT://kafka-headless.kafka.svc.cluster.local:9092"

usage() {
  echo "Usage: $0 [install|upgrade|dashboards|help]"
  echo "  install     Install kube-prometheus-stack + kafka-exporter"
  echo "  upgrade     Upgrade kube-prometheus-stack + kafka-exporter"
  echo "  dashboards  Update Grafana dashboards from JSON files"
  echo "  help        Show this help message"
  exit 1
}

ensure_metrics_server() {
  echo "📈 Ensuring Metrics Server is installed..."
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

  echo "🔧 Patching metrics-server for Docker Desktop..."
  kubectl patch deployment metrics-server -n kube-system \
    --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' || true
}

install_stack() {
  echo "🚀 Installing kube-prometheus-stack..."

  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
  helm repo update

  helm install "$HELM_RELEASE" prometheus-community/kube-prometheus-stack \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f "$VALUES_FILE"

  echo "📦 Installing kafka-exporter..."
  helm install kafka-exporter prometheus-community/prometheus-kafka-exporter \
    --namespace "$NAMESPACE" \
    --set kafka.server="$KAFKA_SERVER"
}

upgrade_stack() {
  echo "🔄 Upgrading kube-prometheus-stack..."

  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
  helm repo update

  helm upgrade "$HELM_RELEASE" prometheus-community/kube-prometheus-stack \
    --namespace "$NAMESPACE" \
    -f "$VALUES_FILE"

  echo "⬆️ Upgrading kafka-exporter..."
  helm upgrade kafka-exporter prometheus-community/prometheus-kafka-exporter \
    --namespace "$NAMESPACE" \
    --set kafka.server="$KAFKA_SERVER"
}

update_dashboards() {
  echo "📁 Rebuilding Grafana dashboards from: $DASHBOARD_DIR"

  if [ ! -d "$DASHBOARD_DIR" ]; then
    echo "❌ Dashboard directory '$DASHBOARD_DIR' not found."
    exit 1
  fi

  kubectl create configmap grafana-dashboards \
    --from-file="$DASHBOARD_DIR" \
    --namespace "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "♻️ Restarting Grafana to reload dashboards..."
  kubectl rollout restart deployment "$HELM_RELEASE-grafana" -n "$NAMESPACE"

  echo "✅ Dashboards updated and Grafana restarted."
}

show_status() {
  echo
  echo "🔐 Grafana admin password:"
  kubectl get secret "$HELM_RELEASE-grafana" -n "$NAMESPACE" -o jsonpath="{.data.admin-password}" | base64 -d ; echo

  echo
  echo "📊 Prometheus pod usage:"
  kubectl top pods -n "$NAMESPACE" | grep prometheus || echo "(metrics-server not ready yet)"

  echo
  echo "📊 Grafana pod usage:"
  kubectl top pods -n "$NAMESPACE" | grep grafana || echo "(metrics-server not ready yet)"

  echo
  echo "🔧 Metrics server args:"
  kubectl get deployment metrics-server -n kube-system -o=jsonpath="{.spec.template.spec.containers[0].args}" ; echo
}

# === Main ===
if [ $# -ne 1 ]; then usage; fi

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
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    echo "❌ Unknown command: $1"
    usage
    ;;
esac
