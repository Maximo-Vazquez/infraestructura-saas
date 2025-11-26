# Infraestructura General - Cluster NAS

Este repositorio contiene la configuración de enrutamiento y secretos
del cluster.

## Prerrequisitos en el NAS

1.  Tener **k3s** o Kubernetes instalado.
2.  Tener **Nginx Ingress Controller** habilitado.

## Paso 0: Instalar Nginx Ingress Controller (una sola vez)

El controlador se despliega con NodePort (puertos 61180/61443 que permite QNAP). Opciones:

1. Manual en el NAS:
    ```bash
    kubectl apply -f ingress/ingress-controller.yaml
    kubectl -n ingress-nginx get pods,svc
    ```
2. Boton GitHub Actions: ejecuta el workflow **Bootstrap Nginx Ingress Controller** (workflow_dispatch). Usa las mismas credenciales NAS que el deploy manual.

Recuerda abrir/forwardear en el NAS/Router los puertos 61180 (HTTP) y 61443 (HTTPS) hacia afuera si quieres exponer servicios publicamente.

## Paso 1: Configurar Secretos (Primera vez)

Ver el archivo `secrets-templates/db-credentials.txt`. Ejecutar esos
comandos manualmente en la terminal del NAS para conectar a la BD.

## Paso 2: Aplicar Enrutamiento (Ingress)

Cada vez que añadas un dominio nuevo, edita
`ingress/global-ingress.yaml` y ejecuta:

``` bash
kubectl apply -f ingress/global-ingress.yaml 
```

### Debugging

Si algo falla con las rutas:

    kubectl get ingress
    kubectl describe ingress ingress-principal

------------------------------------------------------------------------

### ¿Cómo se usa este repositorio en el día a día?

A diferencia de las apps, **este repo no necesita tanta
automatización**.

1.  **Día 1:** Entras a tu NAS por SSH, clonas este repo, creas los
    secretos manualmente (copiando del `.txt`) y aplicas el Ingress
    (`kubectl apply -f ingress/...`).
2.  **Día 100:** Decides comprar otro dominio `tienda.com`.
    -   Editas `ingress/global-ingress.yaml` en tu PC.
    -   Haces `git push`.
    -   Entras al NAS, haces `git pull` y
        `kubectl apply -f ingress/global-ingress.yaml`.

Es simple, seguro y mantiene las "llaves del reino" (Ingress y Secretos)
separadas de

Nota: Habilitar o deshabilitar el servidor Kubernetes no afecta otras
cargas de trabajo.\
El puerto de host 6443 se utiliza para el servidor de API de
Kubernetes.\
Solo los puertos de host 61000-62000 están disponibles para las
aplicaciones dentro del clúster de Kubernetes.\
El sistema creará un usuario llamado "admin-user" para la interfaz web
de Kubernetes (panel de control). Este usuario tendrá privilegios
administrativos en el panel de control durante la implementación de
Kubernetes.

# 📘 Guía de Despliegue Manual: Infraestructura NAS

Este documento describe el flujo de trabajo **"Pull-based"** para
gestionar la configuración global del cluster (Ingress y Secretos).

A diferencia de las aplicaciones (que usan CI/CD automático), la
infraestructura se gestiona manualmente para garantizar mayor control y
seguridad sobre los cambios de red críticos.

------------------------------------------------------------------------

## 🔄 El Flujo de Trabajo (Resumen Visual)

El proceso sigue un ciclo de **Edición en PC** -\> **Sincronización en
Nube** -\> **Aplicación en NAS**.

``` mermaid
graph LR
    A[💻 Tu PC] -- git push --> B(☁️ GitHub)
    B -- git pull --> C[🏠 NAS Server]
    C -- kubectl apply --> D(☸️ Kubernetes Cluster)
```

## 🛠️ Fase 1: Configuración Inicial (Solo la primera vez)

Antes de poder actualizar, necesitas descargar el repositorio en tu NAS.

Conéctate al NAS por SSH:

``` bash
ssh usuario@192.168.1.XX
```

Clona el repositorio: Elige una carpeta donde guardarás las
configuraciones (ej: `/home/usuario/k8s-configs`).

``` bash
mkdir -p ~/k8s-configs
cd ~/k8s-configs
git clone https://github.com/TU_USUARIO/infraestructura-general.git
```

## 🚀 Fase 2: Ciclo de Actualización Rutinaria

Sigue estos pasos cada vez que necesites agregar un dominio, cambiar una
regla de ruteo o modificar configuraciones globales.

### Paso A: En tu Computadora (PC)

Edita los archivos YAML (ej: `ingress/global-ingress.yaml`).

Guarda los cambios y súbelos a GitHub:

``` bash
git add .
git commit -m "Agregado nuevo dominio para saas"
git push origin main
```

### Paso B: En el NAS (Aplicar Cambios)

Accede por SSH y entra a la carpeta del repo:

``` bash
cd ~/k8s-configs/infraestructura-general
```

Descarga los cambios (Pull):

``` bash
git pull origin main
```

Aplica los cambios al Cluster:

``` bash
kubectl apply -f ingress/global-ingress.yaml
```

Salida esperada:

    ingress.networking.k8s.io/ingress-global configured

## ⚡ Cheat Sheet (Comando Rápido)

``` bash
git pull && kubectl apply -f ingress/
```

## 🆘 Solución de Problemas Comunes

### 1. Error: "Git Pull Failed" (Conflictos locales)

Si alguna vez editaste un archivo directamente en el NAS por error, git
pull fallará.

Solución:

``` bash
git fetch --all
git reset --hard origin/main
```

### 2. Error: "Ingress no funciona"

Si aplicaste el YAML pero la página no carga:

Verifica que no haya errores de sintaxis.

Consulta el estado:

``` bash
kubectl get ingress
kubectl describe ingress ingress-global
```

### 3. Recordatorio sobre Secretos

Los Secretos de Base de Datos **NO** se actualizan con este flujo.

Si cambias la contraseña de la BD debes borrar y recrear:

``` bash
kubectl delete secret db-credentials
kubectl create secret generic db-credentials ...
```

(ver plantilla local)
