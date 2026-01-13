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

## Dominios y DNS (Cloudflare)

El sistema utiliza **Cloudflare** para gestión de DNS y seguridad (Proxy).

- **Host Principal:** `bibliotecadvschaco.com` (SaaS)
- **Subdominios Tenants:** `*.bibliotecadvschaco.com` (Indumentaria/Tiendas)
- **TLS:** Gestionado por el Ingress (Let's Encrypt) + Cloudflare (Full SSL).

### Configuración DNS Requerida (Cloudflare)
1.  **Registro A (@):** Apunta a tu IP Pública (Proxy Naranja 🟧).
2.  **Registro A (www):** Apunta a tu IP Pública (Proxy Naranja 🟧).
3.  **Registro A (tienda):** Apunta a tu IP Pública (Proxy Naranja 🟧).
4.  **Registro A (*):** Apunta a tu IP Pública (Proxy Naranja 🟧) - para nuevos tenants automáticos.

### Configuración de Red (Router/NAS)
**Opción Recomendada (Router):** Redirige los puertos **80** (Externo) a **61180** (NAS IP) y **443** (Externo) a **61443** (NAS IP) del NAS. Esto envía el tráfico directo a Kubernetes, saltando el proxy del NAS.

## Página temporal de mantenimiento

HTML separado en `ingress/maintenance/index.html` (no incrustado en YAML).

1. Construye y aplica con Kustomize (configMap desde el HTML):
   ```bash
   kubectl apply -k ingress/maintenance
   ```
   Esto crea:
   - ConfigMap `maintenance-page` desde `index.html` (sin hash de nombre).
   - Deployment `maintenance-page` (nginx).
   - Service `maintenance-service`.
2. Aplica el Ingress:
   ```bash
   kubectl apply -f ingress/global-ingress.yaml
   ```
   (Ya apunta a `maintenance-service` en los hosts principales y catch-all).
3. Cuando las apps estén listas:
   - Cambia en `ingress/global-ingress.yaml` los `service.name` a:
     - `mi-nas-vaz.myqnapcloud.com` -> `indumentaria-service`
    - `sistema.mycloudnas.com` -> `saas-service`
     - catch-all -> lo que quieras por defecto (ej. `indumentaria-service`)
   - Vuelve a aplicar: `kubectl apply -f ingress/global-ingress.yaml`

## Automatización del flujo completo (GitHub Actions)

- Workflow manual `Deploy Infra Completa (Controller + Maintenance + Ingress)`:
  - Copia la carpeta `ingress/` al NAS.
  - Instala/actualiza el controller (`ingress/ingress-controller.yaml`).
  - Aplica la página de mantenimiento (`kubectl apply -k ingress/maintenance`).
  - Aplica el Ingress con backend seleccionado:
    - `backend_mode: maintenance` (por defecto) usa `ingress/global-ingress.yaml` (muestra la página temporal).
    - `backend_mode: apps` usa `ingress/global-ingress-apps.yaml` (requiere `indumentaria-service` y `saas-service` creados).

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

## PostgreSQL en el NAS (fuera de Kubernetes)

- Contenedor unico en el NAS (docker/podman) con datos en `/share/Public/postgres-data` (ruta pedida `public/postgres-data`) y backups en `/share/Public/postgres-backups`.
- Workflow nuevo: **Gestion Postgres NAS** (`.github/workflows/postgres-nas.yml`, `workflow_dispatch`).
  - Secrets requeridos en el repo: `NAS_HOST`, `NAS_USER`, `NAS_SSH_KEY`, `NAS_PORT` (ya existentes) y **`POSTGRES_PASSWORD`**. Opcional: `POSTGRES_USER`.
  - Inputs: `task` (`start`, `backup`, `restart`, `status`), `data_dir`, `backup_dir`, `port` (overrides opcionales).
  - Boton de backup: ejecuta `task=backup` y deja `postgres-YYYYMMDD-HHMMSS.sql` en `backup_dir`.
- Script reusable en el NAS: `scripts/postgres-nas.sh` (se copia al NAS por el workflow). Uso manual por SSH:
  ```bash
  export POSTGRES_PASSWORD="tu_password"
  ./scripts/postgres-nas.sh start   # crea/arranca contenedor nas-postgres (sin crear DB inicial)
  ./scripts/postgres-nas.sh backup  # genera dump en /share/Public/postgres-backups
  ./scripts/postgres-nas.sh status  # estado rapido
- Bases adicionales (ej. Indumentaria, software_venta): créalas por SSH con psql:
  ```bash
  export PGPASSWORD="tu_password"
  psql -h 127.0.0.1 -p 5432 -U "$POSTGRES_USER" -c 'CREATE DATABASE "Indumentaria";'
  psql -h 127.0.0.1 -p 5432 -U "$POSTGRES_USER" -c 'CREATE DATABASE "software_venta";'
  ```
  ```
- Conecta las apps con el secreto `db-credentials` (`secrets-templates/db-credentials.txt`): host = IP del NAS, puerto = 5432 (o el que expongas), user/password los mismos del contenedor.
