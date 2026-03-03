# S3 local para media en VPS (MinIO)

Esta guia describe como usar MinIO en Kubernetes (VPS) como almacenamiento S3-compatible para media de `saas` e `indumentaria`.

## Objetivo

- Persistir media fuera de los pods/apps.
- Mantener objetos privados.
- Entregar archivos con URLs firmadas temporales.
- Separar apps por prefijos en un bucket unico.

## Arquitectura

- Endpoint S3 publico: `https://s3.indutienda.com`
- Bucket unico: `media`
- Prefijos:
  - SaaS: `saas/`
  - Indumentaria: `indumentaria/`
- Usuarios S3:
  - Se crean desde `MINIO_SAAS_ACCESS_KEY` y `MINIO_INDUMENTARIA_ACCESS_KEY`.
  - Cada usuario queda restringido al prefijo de su app.

## Prerrequisitos

1. DNS:
- Crear registro `A` para `s3.indutienda.com` apuntando al VPS.

2. Certificados:
- `cert-manager` + `ClusterIssuer letsencrypt-prod` funcionando.

3. GitHub Secrets en este repo:
- `MINIO_ROOT_USER`
- `MINIO_ROOT_PASSWORD`
- `MINIO_SAAS_ACCESS_KEY`
- `MINIO_SAAS_SECRET_KEY`
- `MINIO_INDUMENTARIA_ACCESS_KEY`
- `MINIO_INDUMENTARIA_SECRET_KEY`

## Despliegue

El workflow [`deploy-full-vps.yml`](../.github/workflows/deploy-full-vps.yml) ahora:

1. Aplica secretos de MinIO.
2. Despliega manifests de `ingress/minio`.
3. Espera `deployment/minio` en Ready.
4. Re-ejecuta `job/minio-bootstrap` para:
- asegurar bucket `media`
- recrear politicas por prefijo
- recrear usuarios por app

Para rotar credenciales sin despliegue completo, usar workflow:
- [`s3-credentials-vps.yml`](../.github/workflows/s3-credentials-vps.yml)
- Aplica secrets MinIO, reinicia `deployment/minio` (opcional por input) y re-ejecuta bootstrap.

Comando manual equivalente en el VPS:

```bash
kubectl apply -k ingress/minio
kubectl -n default rollout status deployment/minio --timeout=180s
kubectl -n default delete job minio-bootstrap --ignore-not-found
kubectl -n default apply -f ingress/minio/bootstrap-job.yaml
kubectl -n default wait --for=condition=complete --timeout=180s job/minio-bootstrap
```

## Verificacion de infraestructura

```bash
kubectl -n default get pods,svc,ingress | grep -E "minio|minio-api-ingress"
kubectl get pv minio-pv
kubectl -n default get pvc minio-pvc
kubectl -n default logs job/minio-bootstrap --tail=200
```

Esperado:
- `minio` en estado `Running`
- `minio-pvc` en `Bound`
- `minio-api-ingress` publicado para `s3.indutienda.com`
- `minio-bootstrap` `Complete`

## Cambios requeridos en SaaS e Indumentaria

Esta seccion es para aplicar en los repos de apps (no en este repo).

### 1) Dependencias

Agregar:

```txt
django-storages
boto3
```

### 2) Variables de entorno

Comunes:

```env
USE_S3_MEDIA=true
AWS_S3_ENDPOINT_URL=https://s3.indutienda.com
AWS_STORAGE_BUCKET_NAME=media
AWS_S3_REGION_NAME=us-east-1
AWS_S3_SIGNATURE_VERSION=s3v4
AWS_S3_ADDRESSING_STYLE=path
AWS_QUERYSTRING_AUTH=true
AWS_QUERYSTRING_EXPIRE=3600
AWS_DEFAULT_ACL=
AWS_S3_FILE_OVERWRITE=false
```

Por app:

- SaaS:
  - `AWS_ACCESS_KEY_ID=$MINIO_SAAS_ACCESS_KEY`
  - `AWS_SECRET_ACCESS_KEY=$MINIO_SAAS_SECRET_KEY`
  - `AWS_MEDIA_LOCATION=saas`

- Indumentaria:
  - `AWS_ACCESS_KEY_ID=$MINIO_INDUMENTARIA_ACCESS_KEY`
  - `AWS_SECRET_ACCESS_KEY=$MINIO_INDUMENTARIA_SECRET_KEY`
  - `AWS_MEDIA_LOCATION=indumentaria`

### 3) Settings Django (patron recomendado)

```python
import os

USE_S3_MEDIA = os.getenv("USE_S3_MEDIA", "false").lower() == "true"

if USE_S3_MEDIA:
    AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID", "")
    AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY", "")
    AWS_STORAGE_BUCKET_NAME = os.getenv("AWS_STORAGE_BUCKET_NAME", "media")
    AWS_S3_ENDPOINT_URL = os.getenv("AWS_S3_ENDPOINT_URL", "https://s3.indutienda.com")
    AWS_S3_REGION_NAME = os.getenv("AWS_S3_REGION_NAME", "us-east-1")
    AWS_S3_SIGNATURE_VERSION = os.getenv("AWS_S3_SIGNATURE_VERSION", "s3v4")
    AWS_S3_ADDRESSING_STYLE = os.getenv("AWS_S3_ADDRESSING_STYLE", "path")
    AWS_QUERYSTRING_AUTH = os.getenv("AWS_QUERYSTRING_AUTH", "true").lower() == "true"
    AWS_QUERYSTRING_EXPIRE = int(os.getenv("AWS_QUERYSTRING_EXPIRE", "3600"))
    AWS_DEFAULT_ACL = None
    AWS_S3_FILE_OVERWRITE = os.getenv("AWS_S3_FILE_OVERWRITE", "false").lower() == "true"
    AWS_MEDIA_LOCATION = os.getenv("AWS_MEDIA_LOCATION", "saas")

    STORAGES = {
        "default": {
            "BACKEND": "storages.backends.s3.S3Storage",
            "OPTIONS": {
                "bucket_name": AWS_STORAGE_BUCKET_NAME,
                "location": AWS_MEDIA_LOCATION,
            },
        },
        "staticfiles": {
            "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
        },
    }
else:
    MEDIA_URL = "/media/"
    MEDIA_ROOT = os.path.join(BASE_DIR, "media")
```

Notas:
- No hardcodear URLs permanentes en DB.
- Guardar keys relativas (`saas/...` o `indumentaria/...`).
- En API/UI usar `campo_archivo.url` para URL firmada temporal.

### 4) Migracion inicial local -> S3

Script de ejemplo (ejecutar una vez por app):

```python
from django.core.files.storage import default_storage
from myapp.models import MiModelo

for obj in MiModelo.objects.exclude(imagen=""):
    f = obj.imagen
    if not f:
        continue
    # fuerza re-save para re-subir al storage actual (S3)
    f.open("rb")
    obj.imagen.save(f.name.split("/")[-1], f.file, save=True)
    f.close()
```

Validar:
- conteo de objetos en S3 por prefijo
- muestreo de apertura de URLs firmadas
- backup previo de media local antes de migrar

## Troubleshooting

1. `SignatureDoesNotMatch`
- Revisar `AWS_S3_ADDRESSING_STYLE=path`.
- Revisar endpoint exacto `https://s3.indutienda.com`.
- Verificar hora del servidor (NTP).

2. `AccessDenied`
- Verificar que la app usa credenciales correctas por prefijo.
- Revisar logs del `job/minio-bootstrap`.

3. URLs firmadas no abren externamente
- Confirmar DNS y certificado de `s3.indutienda.com`.
- Confirmar Ingress `minio-api-ingress` y service `minio-api`.
