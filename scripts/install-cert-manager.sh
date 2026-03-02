#!/usr/bin/env bash
# Script para instalar Cert-Manager si no existe (o está incompleto) en el cluster.

set -euo pipefail

echo "Verificando instalación de Cert-Manager..."

if kubectl get namespace cert-manager >/dev/null 2>&1 && kubectl get deployment cert-manager -n cert-manager >/dev/null 2>&1; then
  echo "✅ Cert-Manager ya está instalado."
  exit 0
fi

echo "⚠️ Cert-Manager no encontrado (o incompleto). Instalando/actualizando..."

# Instalar Cert-Manager (v1.13.3)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

echo "⏳ Esperando a que Cert-Manager inicie..."
kubectl rollout status -n cert-manager deployment/cert-manager --timeout=180s
kubectl rollout status -n cert-manager deployment/cert-manager-webhook --timeout=180s
kubectl rollout status -n cert-manager deployment/cert-manager-cainjector --timeout=180s

echo "✅ Cert-Manager instalado correctamente."
