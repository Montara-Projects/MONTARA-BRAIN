# CORE V2 — runbook de arranque Linux independiente

**Efrain-001 · 25/11/2026 · Preparación documental; NO ejecutar todavía.**
Alcance: H0/H1, VM nueva Linux x86-64, 4 vCPU/8 GiB objetivo, SSD local. Proveedor, repo, presupuesto, destino y autorización de ejecución pendientes de FER/JM. No tocar V1, Oracle, credenciales existentes ni instalar agentes por defecto. Alfred registra el encargo y panel; este documento no asigna implementación.

## 0. Puerta de entrada — FER
- Confirmar destino V2 inequívoco, imagen Linux soportada, consola de rescate, capacidad y coste; confirmar autorización para preparar VM y, aparte, instalar release. Propuesta Ubuntu Server 24.04 LTS; Python 3.11 aislado (no sustituir Python del SO). Alternativa otra distribución soportada con perfil explícito.
- Registrar fuera de GitHub público IP/DNS, fingerprints SSH obtenidos de fuente confiable, identidad administrativa, método de recuperación, permisos y secretos; solo referencias no sensibles en BRAIN. SSH directo autorizado primero; SentinelX puente sigue NO GO, slot Oracle intacto. Conector opcional solo después de validar destino/permisos/cuotas.
- Inventario de solo lectura, desde sesión inequívoca de V2:
  ```sh
  uname -m; cat /etc/os-release
  nproc; free -h; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
  df -h /; df -i /; stat -fc %T /sys/fs/cgroup
  timedatectl status; systemctl --version
  ss -lntup; systemctl --failed --no-pager
  ```
  Aceptación: x86_64, cgroup v2, 8 GiB nominales, almacenamiento local suficiente, reloj sincronizado, sin servicios inesperados; detener ante destino dudoso, capacidad insuficiente o errores críticos. No publicar salidas crudas con datos sensibles.

## 1. Acceso seguro y base del sistema
- FER conserva consola de rescate. Crear administrador nominal con clave SSH propia y sudo autorizado; comprobar acceso y sudo en segunda sesión antes de desactivar password, keyboard-interactive y root remoto. Validar configuración con `sshd -t` y efectiva con `sshd -T`; recargar (no cerrar primera sesión). Verificar clave del host; nunca StrictHostKeyChecking=no, agent forwarding ni claves privadas compartidas.
- Política de firewall local declarativa (nftables o UFW, una sola autoridad), entrada denegada por defecto; permitir SSH desde origen autorizado antes de activarla, sin perder consola; 80/443 solo al aprobar edge/TLS. API interna loopback, nada de SQLite/worker público. Egress mínimo compatible con DNS, hora, paquetes y OIDC. Firewall del proveedor, si existe, complemento externo, no requisito del Core. Verificar desde segunda sesión y prueba negativa.
- Revisar/instalar parches de seguridad tras autorización, reiniciar si necesario con ventana y consola; registrar imagen, paquetes/versiones y estado. Sin autoapagado ni reinicio automático mientras existan jobs. UTC, rotación journald/logs y límite de disco. No instalar stack cloud, Docker, GPU, PostgreSQL, modelos IA ni servicios innecesarios.

## 2. Dependencias y build (H1)
- Paquetes candidatos Debian/Ubuntu: ca-certificates, git (solo build si necesario), ffmpeg/ffprobe, libsndfile1, sqlite3; añadir librerías nativas únicamente si import closure lo exige. Herramientas de compilación solo en build si faltan wheels. Repositorios oficiales, firma y versiones registradas. Confirmar Python 3.11 por runtime de origen verificable, venv y toolchain fijados; no pip global, no curl|sh sin revisión.
- Recuperar [lock Linux V1](https://github.com/Montara-Projects/Montara/blob/7113fd2801558cc31bf9b2c1bfab360c7faa40ca/deploy/requirements-linux.lock) solo como inventario (3.11 x86_64, no hashes en el fragmento consultado), [requirements](https://github.com/Montara-Projects/Montara/blob/7113fd2801558cc31bf9b2c1bfab360c7faa40ca/requirements.txt) y [perfil Eugenia](https://github.com/Montara-Projects/MONTARA-BRAIN/issues/1#issuecomment-7150771137). No copiar íntegro: V1 arrastra Whisper, Mixer, OpenAI y tests de navegador que H2 no necesita por defecto. Eugenia confirma import closure/compatibilidad y licencias FFmpeg/codecs, antes de distribuir.
- En repo producto aprobado, generar lock V2 con hashes por target, wheelhouse o paquete autocontenido verificable y manifiesto (SHAs aprobados Core/Engine, toolchain, OS/arch, dependencias nativas, schema/contratos, migraciones, hashes de archivos/artefacto, licencias). No descargar modelos por arranque. CI/build separado de runtime; build y render no simultáneos en VM de 8 GiB. Dos builds limpios con árbol normalizado idéntico, explicar diferencias de metadatos; conservar hash del artefacto exacto probado, no reconstruir para promocionar.
- Comandos de verificación futuros desde runtime/artefacto, no desde checkout:
  ```sh
  "$PYTHON_V2" --version
  "$PYTHON_V2" -m pip check
  ffmpeg -version; ffprobe -version
  ffmpeg -hide_banner -encoders
  sqlite3 --version
  sha256sum -c SHA256SUMS
  ```
  PYTHON_V2 y SHA256SUMS son interfaces propuestas; ejecutar solo con ruta/manifest aprobado, en directorio del artefacto y sin exponer secretos. Smoke de imports reales y worker aislado obligatorio; `pip check` no prueba librerías nativas ni imports. Aprender de [#293](https://github.com/Montara-Projects/Montara/issues/293): paquete incompleto pese a fuentes correctas; no heredar overlays ni parchear release activo.

## 3. Aislamiento e instalación declarativa (H1)
Rutas candidatas (no existen aún): /opt/montara-core/releases/<id> (root, lectura runtime); /opt/montara-core/current (enlace atómico); /etc/montara-core/ (perfil externo y credenciales restringidas); /var/lib/montara-core/ (SQLite y datos durables); /var/cache/montara-core/ y /var/lib/montara-core/work/ (temporales y scratch con TTL). Backup consistente SQLite/artefactos fuera de scratch; no confundir copia en mismo disco con DR.
- Identidad de servicio sin login/sudo, separada de administrador/build; release inmutable, sin acceso a claves admin ni V1. Core autoridad del dominio; workspace Engine por owner/project/job/attempt, permisos/validaciones y publicación por contrato (no confiar solo en UID único). Usar systemd y cgroup v2; NoNewPrivileges, ProtectSystem=strict, PrivateTmp, ProtectHome y rutas RW explícitas donde sean compatibles; probar contra worker real.
- Presupuesto inicial: máximo 1 job en curso; worker MemoryMax=4G provisional, reservar resto para Core/SO/margen, controlar CPU/tasks y disco; no suponer que un job equivale a un proceso FFmpeg, limitar concurrencia interna según Eugenia. 10–15 GiB libres tras instalación (objetivo 15), preflight por trabajo y workspace sintético inicial 2 GiB. Admitir solo si espacio suficiente para temporales, output y reserva. Sin autoapagado activo ni jobs paralelos.
- Instalador futuro: preflight → diff/dry-run → comprobar hashes y propiedad → preparar release nuevo → verificar imports/worker desde paquete → migración/backup consistente si aplica → activar enlace y unidad versionada → health/smoke. Segunda instalación del mismo artefacto/perfil no cambia estado funcional; drift real bloquea promoción. No sobrescribir recursos ajenos ni secretos; no editar runtime a mano. Rollback a release previo solo con schema compatible y preservando nuevas escrituras; si no, forward-fix probado, no restaurar DB antigua indiscriminadamente.
- Edge TLS y OIDC real en H2: configuración externa, cliente/callback/issuer específicos de V2, sin reutilizar credenciales V1. Core sin SDK de proveedor; SQLite y storage local, cloud off; no medios reales.

## 4. Gates de salida (Efrain + Quasimodo, tras autorización)
| Gate | Evidencia mínima / criterio |
|---|---|
| Host listo | Inventario saneado, SSH por clave, rescate y firewall comprobados; no puertos públicos imprevistos, cgroup v2 y disco/memoria suficientes. |
| Paquete listo | Manifest/hashes y dos builds, doble install idempotente, import y worker real desde paquete, fallo cerrado ante dependencia ausente, health y drift; sin secretos en logs. |
| Aislamiento | Identidad no privilegiada, lectura/escritura denegada fuera de rutas autorizadas, dos owners sin acceso cruzado, cloud desactivado, límites cgroup/disco efectivos. |
| H2 (no sustituye gate H1) | Login OIDC → proyecto → fixture local 20s/2 cámaras 1080p/WAV → receta → job/Engine → MP4 real decodificable → reapertura; medir RSS/OOM, CPU steal, espacio/IO; retry/restart/rollback compatible y no duplicación de outputs/cuotas. |

Evidencia: commit y SHA del release, perfil no secreto, checks y resultados PASS/FAIL/NO EJECUTADO, cambios manuales, pasos de recuperación; anexar resultados saneados al issue de encargo. Parar ante fallo de acceso/aislamiento, hash, import, migración o recursos; no remediar mediante hotfix no declarado. Portabilidad en segundo proveedor después de H2, no requisito de arranque.

**Estado:** todo propuesto/no ejecutado. Pendientes: destino y autorización FER, repo/contratos Archi, lock y closure Eugenia, gates Quasimodo; Alfred coordina. No contratación, instalaciones, pruebas de runtime, cambios de infraestructura o producto.
