# Backups diarios en VPS (Postgres + Media MinIO)

Esta guia documenta los backups automaticos diarios para el entorno VPS.

## Alcance

- Backup diario de Postgres (`pg_dumpall` comprimido).
- Backup diario de media de MinIO (snapshot de `/srv/minio-data`).
- Retencion automatica de 7 dias.
- Destino local en el VPS.

## Workflow

- Archivo: `.github/workflows/backup-daily-vps.yml`
- Programacion: `06:00 UTC` todos los dias (`03:00` hora Argentina, ART/UTC-3).
- Tambien permite ejecucion manual (`workflow_dispatch`).

### Inputs manuales

- `run_postgres`: `true/false`
- `run_media`: `true/false`
- `retention_days`: default `7`

## Rutas por defecto

- Postgres backups: `$HOME/postgres-backups`
- Media backups: `$HOME/minio-backups`
- Datos MinIO: `/srv/minio-data`

## Scripts usados

- `scripts/postgres-vps.sh`
  - acciones: `start|deploy|backup|prune|status|restart|stop`
  - `backup` genera `postgres-YYYYMMDD-HHMMSS.sql.gz`
  - aplica prune automatico por retencion

- `scripts/minio-vps-backup.sh`
  - acciones: `backup|prune|status`
  - `backup` genera `minio-data-YYYYMMDD-HHMMSS.tar.gz`
  - valida integridad basica del tar
  - aplica prune automatico por retencion

## Ejecucion manual

Desde GitHub:
1. Actions -> `Backup Diario VPS (Postgres + MinIO Media)`
2. Run workflow
3. Elegir inputs si queres solo uno de los dos backups.

Desde VPS (manual):

```bash
export POSTGRES_PASSWORD="tu_password"
export POSTGRES_USER="postgres"
export PG_RETENTION_DAYS=7
export MINIO_RETENTION_DAYS=7

~/deployments/backups/postgres-vps.sh backup
~/deployments/backups/minio-vps-backup.sh backup
```

## Verificacion

```bash
ls -lah ~/postgres-backups | head
ls -lah ~/minio-backups | head
du -sh ~/postgres-backups ~/minio-backups
```

Esperado:
- hay archivos recientes `postgres-*.sql.gz`
- hay archivos recientes `minio-data-*.tar.gz`
- no hay archivos de mas de 7 dias

### Verificacion cuando entras como root (caso comun)

Si el workflow corre con usuario `deploy`, los backups no estaran en `/root/...`.
Verifica con rutas absolutas:

```bash
ls -lah /home/deploy/postgres-backups | head
ls -lah /home/deploy/minio-backups | head
du -sh /home/deploy/postgres-backups /home/deploy/minio-backups
```

Salida esperada de ejemplo:
- `postgres-YYYYMMDD-HHMMSS.sql.gz`
- `minio-data-YYYYMMDD-HHMMSS.tar.gz`
- tamanos distintos de cero en ambas carpetas

## Restore

### Restore Postgres

1. Elegir backup `postgres-*.sql.gz`.
2. Restaurar:

```bash
gunzip -c /ruta/postgres-YYYYMMDD-HHMMSS.sql.gz | docker exec -i vps-postgres psql -U "$POSTGRES_USER" postgres
```

Si usas podman, reemplaza `docker` por `podman`.

### Restore Media MinIO

1. Escalar MinIO a 0:

```bash
kubectl -n default scale deployment/minio --replicas=0
```

2. Restaurar snapshot sobre `/srv/minio-data`:

```bash
sudo rm -rf /srv/minio-data
sudo mkdir -p /srv
sudo tar -xzf /ruta/minio-data-YYYYMMDD-HHMMSS.tar.gz -C /srv
```

3. Escalar MinIO a 1:

```bash
kubectl -n default scale deployment/minio --replicas=1
kubectl -n default rollout status deployment/minio --timeout=180s
```

4. Verificar acceso desde apps (URLs firmadas).

## Troubleshooting

1. `Error: Define POSTGRES_PASSWORD`
- Falta secret `POSTGRES_PASSWORD` en GitHub o export local.

2. `Container vps-postgres is not running`
- Ejecutar `scripts/postgres-vps.sh start`.

3. `MinIO data directory not found: /srv/minio-data`
- Confirmar ruta y que MinIO use ese PV/hostPath.

4. Backups no se ejecutan en horario
- Verificar que el workflow no este deshabilitado en GitHub Actions.
- Confirmar cron en UTC y conversion a ART (`06:00 UTC = 03:00 ART`).

## Riesgo conocido

Los backups quedan en el mismo VPS. Esto no protege ante perdida total del host.
Siguiente fase recomendada: replicacion offsite (otro servidor o S3 externo).
