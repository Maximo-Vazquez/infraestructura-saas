# Infraestructura General - Cluster NAS

Este repositorio contiene la configuración de enrutamiento y secretos del cluster.

## Prerrequisitos en el NAS
1. Tener **k3s** o Kubernetes instalado.
2. Tener **Nginx Ingress Controller** habilitado.

## Paso 1: Configurar Secretos (Primera vez)
Ver el archivo `secrets-templates/db-credentials.txt`. 
Ejecutar esos comandos manualmente en la terminal del NAS para conectar a la BD.

## Paso 2: Aplicar Enrutamiento (Ingress)
Cada vez que añadas un dominio nuevo, edita `ingress/global-ingress.yaml` y ejecuta:

```bash
kubectl apply -f ingress/global-ingress.yaml 
```
Debugging
Si algo falla con las rutas:
```
kubectl get ingress
kubectl describe ingress ingress-principal
```
---

### ¿Cómo se usa este repositorio en el día a día?

A diferencia de las apps, **este repo no necesita tanta automatización**.

1.  **Día 1:** Entras a tu NAS por SSH, clonas este repo, creas los secretos manualmente (copiando del `.txt`) y aplicas el Ingress (`kubectl apply -f ingress/...`).
2.  **Día 100:** Decides comprar otro dominio `tienda.com`.
    * Editas `ingress/global-ingress.yaml` en tu PC.
    * Haces `git push`.
    * Entras al NAS, haces `git pull` y `kubectl apply -f ingress/global-ingress.yaml`.

Es simple, seguro y mantiene las "llaves del reino" (Ingress y Secretos) separadas de