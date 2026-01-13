# Guía de despliegue desde cero (NAS + k3s + Ingress)

Pasos ordenados para levantar el Ingress, la página de mantenimiento y luego las apps.

## 0. Prerrequisitos en el NAS
- k3s/Kubernetes funcionando y `kubectl` accesible (usa `/etc/rancher/k3s/k3s.yaml` si es k3s).
- Puertos abiertos/forwardeados en el NAS o router: `61180` (HTTP) y `61443` (HTTPS) hacia el host del NAS.
- Dominio de entrada: `mi-nas-vaz.myqnapcloud.com` (o CNAMEs que apunten allí).
- TLS se termina en el proxy inverso/QNAP usando su certificado válido. El Ingress recibe HTTP en 61180/61443 desde el proxy.

## 1. Instalar el Nginx Ingress Controller (una sola vez o cuando lo actualices)
Opción manual:
```bash
kubectl apply -f ingress/ingress-controller.yaml
kubectl -n ingress-nginx get pods,svc
```

Opción GitHub Actions (botón):
- Ejecuta el workflow `Bootstrap Nginx Ingress Controller` (workflow_dispatch) en GitHub.
- O ejecuta el workflow `Deploy Infra Completa (Controller + Maintenance + Ingress)` con `backend_mode: maintenance` (aplica controller + página temporal + Ingress).

## 2. Desplegar la página de mantenimiento
Sirve como placeholder para evitar 503 mientras suben las apps.
```bash
kubectl apply -k ingress/maintenance
kubectl -n default get pods,svc | findstr maintenance
```

## 3. Configurar DNS y SSL (Cloudflare + Ingress)

Usaremos **Cloudflare** como proveedor de DNS para aprovechar su seguridad y gestión de certificados simplificada, junto con el Ingress de Kubernetes.

#### 3.1. En Cloudflare
1.  Agrega tu dominio (ej: `bibliotecadvschaco.com`).
2.  Ve a la sección **DNS** y crea los siguientes registros **A**:
    *   **@** (Root) -> Tu IP Pública (con Proxy activado ☁️ Naranja).
    *   **www** -> Tu IP Pública (con Proxy activado ☁️ Naranja).
    *   **tienda** -> Tu IP Pública (con Proxy activado ☁️ Naranja).
    *   (Opcional) **\*** (Wildcard) -> Tu IP Pública (con Proxy activado ☁️ Naranja).
3.  (Para automatización total) Crea un **API Token** con permisos de edición de DNS para usar certificados Wildcard y validación DNS-01.

#### 3.2. En tu NAS (QNAP) / Router
Para que el tráfico llegue al clúster, tienes dos opciones:

*   **Opción A (Recomendada - Zero Touch):** En tu router, redirige los puertos 80 y 443 TCP directamente a la IP local de tu Ingress Controller (`192.168.X.X`). Esto evita usar el proxy del NAS.
*   **Opción B (Proxy Inverso QNAP):** En "Network & File Services" -> "Reverse Proxy", agrega reglas para cada subdominio:
    *   `bibliotecadvschaco.com:443` -> `localhost:61443`
    *   `tienda.bibliotecadvschaco.com:443` -> `localhost:61443`
    *   *Nota: El proxy de QNAP no soporta Wildcards fácilmente.*

## 3.3. Configurar Certificados (Cert-Manager)
El proyecto incluye `issuer-letsencrypt-prod.yaml`.
*   Para dominios exactos (HTTP-01): Funciona "out of the box".
*   Para Wildcards `*.dominio.com` (DNS-01): Requiere configurar un Secret con el API Token de Cloudflare.

## 4. Aplicar el Ingress Global
El archivo maestro es `ingress/global-ingress-apps.yaml`.
```bash
kubectl apply -f ingress/global-ingress-apps.yaml
```
Este archivo ya contiene:
*   `bibliotecadvschaco.com` -> `saas-service`
*   `*.bibliotecadvschaco.com` -> `indumentaria-service`

## 5. Verificación
1.  Entra a `https://bibliotecadvschaco.com` -> Debería cargar tu SaaS.
2.  Entra a `https://tienda.bibliotecadvschaco.com` -> Debería cargar tu tienda.


## 6. Cambiar del placeholder a las apps reales
Cuando `indumentaria-service` y `saas-service` estén desplegados en el mismo namespace (`default`):
1. Edita `ingress/global-ingress.yaml` y cambia los `service.name`:
   - `mi-nas-vaz.myqnapcloud.com` -> `indumentaria-service`
   - `sistema.mycloudnas.com` -> `saas-service`
   - catch-all -> el backend por defecto que prefieras (ej. `indumentaria-service`)
2. Aplica de nuevo:
   ```bash
   kubectl apply -f ingress/global-ingress.yaml
   kubectl describe ingress ingress-principal
   ```
   O bien ejecuta el workflow `Deploy Infra Completa` con `backend_mode: apps` para aplicar `ingress/global-ingress-apps.yaml`.

## 7. Limpieza opcional
- Si ya no necesitas la página de mantenimiento:
  ```bash
  kubectl delete -k ingress/maintenance
  ```
- Mantén el controller activo; solo actualízalo cuando quieras subir versión.

## 8. Flujo resumido (un comando por etapa)
1. Controller: `kubectl apply -f ingress/ingress-controller.yaml`
2. Placeholder: `kubectl apply -k ingress/maintenance`
3. Ingress: `kubectl apply -f ingress/global-ingress.yaml`
4. Swap a apps: editar services en el Ingress y volver a aplicar.

## 9. PostgreSQL standalone en el NAS
- Contenedor docker/podman fuera de Kubernetes. Datos en `/share/Public/postgres-data` (ruta pedida `public/postgres-data`). Backups en `/share/Public/postgres-backups`.
- Workflow: **Gestion Postgres NAS** (`task=start|backup|restart|status`) copia y ejecuta `scripts/postgres-nas.sh` en el NAS. Requiere secrets `NAS_*` y `POSTGRES_PASSWORD` (opcional `POSTGRES_USER`). No crea DB inicial automáticamente.
- Boton de backup: corre el workflow con `task=backup` y deja dumps `postgres-YYYYMMDD-HHMMSS.sql` en la carpeta de backups.
- Manual por SSH:
  ```bash
  export POSTGRES_PASSWORD="tu_password"
  ./scripts/postgres-nas.sh start   # contenedor nas-postgres, sin DB inicial
  ./scripts/postgres-nas.sh backup  # dump en /share/Public/postgres-backups
  ./scripts/postgres-nas.sh status
  ```
- Crear bases (ej. Indumentaria, software_venta):
  ```bash
  export PGPASSWORD="tu_password"
  psql -h 127.0.0.1 -p 5432 -U "$POSTGRES_USER" -c 'CREATE DATABASE "Indumentaria";'
  psql -h 127.0.0.1 -p 5432 -U "$POSTGRES_USER" -c 'CREATE DATABASE "software_venta";'
  ```
- Crea/actualiza el secreto `db-credentials` con host = IP del NAS y puerto = 5432 (o el que uses) para que las apps apunten a esta BD externa, indicando la base correcta para cada app.
