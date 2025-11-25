# Cómo volver a activar el GitHub Actions Runner en tu QNAP

Este documento explica los pasos necesarios para volver a activar el **GitHub Actions Self‑Hosted Runner** dentro del contenedor Ubuntu en tu QNAP cuando este se reinicia o se detiene.

---

## 📌 1. Abrir el contenedor en QNAP
1. Entra al panel del NAS.
2. Ve a **Container Station**.
3. Busca el contenedor donde instalaste el runner (ej. `github-runner`).
4. Haz clic en **Actions → Attach Terminal**.

---

## 📌 2. Entrar como usuario *runner*
Cuando el terminal se abra, aparecerás como `root`.

Ejecuta:

```bash
su - runner
```

Esto cambia al usuario correcto, ya que el runner fue configurado ahí.

---

## 📌 3. Ubicarse en la carpeta del runner

```bash
cd /actions-runner
```

Verifica que existen archivos como:

- `run.sh`
- `config.sh`
- `bin/`
- `externals/`

---

## 📌 4. Iniciar el runner manualmente

Ejecuta:

```bash
./run.sh
```

Si todo está bien, deberías ver:

```text
√ Connected to GitHub
Listening for Jobs
```

Mientras esta pantalla esté activa, tu runner estará **ONLINE** en GitHub Actions.

---

## 📌 5. Qué hacer si el contenedor o el NAS se reinicia

Cada vez que el contenedor se apague o el NAS se reinicie:

1. Abre Container Station  
2. Arranca el contenedor si está detenido  
3. Abre **Attach Terminal**  
4. Ejecuta:

```bash
su - runner
cd /actions-runner
./run.sh
```

¡Y listo!  
El runner quedará nuevamente escuchando trabajos.

---

## 📌 6. Comando rápido de recuperación (versión corta)

```bash
su - runner
cd /actions-runner
./run.sh
```

---

## 📌 7. Detener el runner manualmente

Presiona:

```
Ctrl + C
```

---

## 📌 8. Notas importantes

- El runner NO usa `systemctl` porque el contenedor no ejecuta `systemd`.
- La activación debe hacerse **manualmente** o creando un script de inicio.
- Si cambias el contenedor o reinstalas Ubuntu, deberás volver a configurarlo.

---

## 👍 Listo

Con este documento puedes volver a poner tu runner en funcionamiento en menos de 10 segundos siempre que sea necesario.
