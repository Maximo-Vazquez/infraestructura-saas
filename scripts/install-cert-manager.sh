#!/bin/bash
# Script para instalar Cert-Manager si no existe en el cluster

echo "Verificando instalación de Cert-Manager..."

if kubectl get pods -n cert-manager > /dev/null 2>&1; then
    echo "✅ Cert-Manager ya está instalado."
else
    echo "⚠️ Cert-Manager no encontrado. Instalando..."
    # Instalar Cert-Manager (v1.13.3)
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
    
    echo "⏳ Esperando a que Cert-Manager inicie..."
    kubectl wait --namespace cert-manager \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/instance=cert-manager \
      --timeout=180s
      
    echo "✅ Cert-Manager instalado correctamente."
fi
