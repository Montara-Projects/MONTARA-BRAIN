# Autonomía V2 — candidato de operaciones ordinarias

**NO EJECUTAR.** [Mandato FER/Alfred](https://github.com/Montara-Projects/MONTARA-BRAIN/issues/32#issuecomment-7238440207). Rama aislada. Diseño para piloto Contabo H2.10, no plataforma general. No modifica producto, permisos, servicios ni estado vivo. La alta 2→4 y prueba de proyectos FER/JM se comunicaron; falta marcador final explícito INCREMENTAL_ADMISSION en la evidencia de Alfred. Cierre y revisión de ese gate antes de activar.

## Autoridad y alternativas

- SentinelX real: strict, siete comandos actuales, servicio/script_run/restart/chown/chmod deshabilitados, file_ops sólo workspaces y cola no privilegiada. No acceso administrativo por conector. Conservamos la regla Polkit del worker existente y los siete comandos. #10 se usa sólo para pruebas no privilegiadas; no puente root ni ampliación file_ops.
- Polkit directo para varios servicios sería simple pero permite combinaciones incorrectas de start/stop/restart y no agrupa preflight, lock ni orden de admisión/worker. Un daemon/API administrativo o SSH general agrega superficie y costes; descartados. Se propone **un lanzador cerrado + helper root-owned + sudoers NOPASSWD exacto de cinco comandos**, no sudo general, no shell ni argumentos/rutas libres. La allowlist strict agrega sólo /usr/local/bin/montara-v2-ops; wrapper verifica UID y exactamente un verbo. Sudoers autoriza sólo cinco cadenas de argumentos literales; helper vuelve a verificar EUID/SUDO_USER, argc y enum. Python -I, subprocess argv fijo/env limpio, no eval/shell ni lectura de scripts modificables por agente. No cambios efectivos en este encargo.
- **La autoridad efectiva es el UID compartido sentinelx**, no Efrain como identidad autenticada. Cualquier agente con el mismo conector y permiso efectivo podría usar estas operaciones. Alfred coordina exclusividad y FER autoriza alcance, gastos, destrucción, identidades y promociones materiales. Una firma textual de IA no es control de seguridad. Root/política/manifest de autorización sólo operador humano o autoridad futura separada explícitamente; ningún escritor de workspace puede cambiar helpers, allowlist o sudoers vivos.
- Lock existente del launcher, mismo inode, protege invocaciones cooperantes. No es barrera contra root, otros administradores o uso directo de Polkit por UID comprometido; el permiso anterior sólo arranca el worker, se conserva exactamente. No conceder privilegios nuevos para evitar esa limitación. Coordinación de mantenimiento sin otros writers, no UI durante cierre, sin timer.
- Auditoría sudo y syslog de operación/resultados saneados (sin tokens, UUID, PIDs, paths privados ni mensajes de error crudos). No dar acceso general a journal/DB/secretos. Estado no privilegiado del worker existente sigue disponible mientras lock ocupado.

## Operaciones y alcance

| Operación | Alcance implementado en candidato |
|---|---|
| status | Estados systemd saneados V2 exclusivamente, no secretos. Busy si lock de worker ocupado; usar status previo del worker. |
| start | Desde HTTP/ingress inactivos, worker quiescente/limpio, ACL activa/efectiva, enrolador ausente; comprobar pines/slot/config/4 sujetos, listeners vacíos/UIDs quiescentes; HTTP→health JSON desde UID ingress→ingress→listeners loopback. Alfred comprueba VPC/QUIC/Access/HTTPS exterior antes de dar acceso. |
| stop | Worker quiescente/lock, ingress primero→HTTP, cgroup y listeners vacíos/UIDs sin procesos. ACL permanece; no detener un render en marcha ni reiniciar ante error. Si no se prueba cierre, Alfred fail-close edge. |
| restart | stop y start en el mismo lock, sin reiniciar worker ni resetear fallos; mismo gate externo. |
| backup | Explícitamente después de stop, no downtime sorpresa: roots db/originals/attempts/artifacts de piloto, mismos datos sin escrituras vivas, inventario no symlinks/especiales/mounts/hardlinks externos, límite 20k entradas, 4 GiB, 2 backups máximo y margen 2 GiB + copia DB; tar root-only 0600 y manifest, verifica todos los contenidos/digests, vuelve a inventariar, comprueba SQLite schema5/quick_check/FK sobre copia temporal del archivo (no DB viva), publicación por rename/fsync, no borrado de backups. |
| worker | Mantiene start/estado y Polkit anteriores. Corrige falso negativo en launcher con una sola lectura de estado y ramas 1/0 retenido, 0/0 metadato no disponible; ambas exigen RC systemctl0, inactive/dead/MainPID0/Result success. No afirmar publicación ni exit histórico por rama 0/0. Además no arranca si HTTP/ingress/ACL no activos. Sin retry. |

Backup local data-only no es DR fuera de host, no incluye secretos, config ni runtime-home (banco sintético reproducible separado); no garantiza recuperación de almacenamiento físico. El archivo contiene datos/DB privados y nunca se expone al agente. No copiar ni descargar backup a GitHub. Verificación de DB de copia no reemplaza validación de esquema de Core ni garantiza restauración. Retención límite devuelve STOP, no borra. Restauración requiere incidente, aprobación FER, prueba de restauración aislada con artefactos/recibos y corte; no restaurar DB antigua sobre writes actuales. Si hay publicación ambigua, Core conserva autoridad: procedimiento recover/interrupt del intento exacto, con quiescencia comprobada y decisión explícita. No implementar stop/kill activo ni recover/interrupt genérico ahora; worker one-shot tiene RuntimeMaxSec600, no interrupción rutinaria. No autorizar comandos destructivos para evitar una futura intervención hipotética.

### Promoción/rollback: contrato siguiente, no permiso hoy

No hay aún release candidato material compatible revisado. El perfil de Core contiene rutas renderer/engine absolutas y el wheel instalado es exacto; mover current a ciegas es incorrecto. Para la primera promoción del fixture, usar el release/manifest aprobado y reconciliar config/pines con Archi. En sucesivas promociones, sólo candidato/predecesor exactos fijados en manifiesto root-owned de autorización (commit/tree, hashes wheel/closure y units, versión de schema, rutas canónicas, pines banco, compatibilidad de lectura/escritura y rollback, autorización explícita de FER, sin args libres). No consumir artefactos desde workspace mutable como root; preparar y verificar en espacio no privilegiado y copiar a staging root verificado por digest. Preflight de espacio/compatibilidad, backup consistente, cerrar admisión, verificar quiescencia, instalar slot inmutable nuevo, cambio de current/config coordinado y atómico en lo posible, health local y gate exterior, conservar slot anterior y recibos. Rollback sólo release previamente autorizado y compatible con DB vigente; nunca restaurar DB pre-promoción automáticamente. Si schema incompatible, stop y plan de recuperación aprobado. No permitir promoción/rollback destructivo por un nombre de rama, URL o firma de chat. No implementar manifest genérico ni grants vacíos antes de candidato real; la autorización material sigue siendo FER. Objetivo posterior: preautorizar sólo pareja exacta y ejecución por helper, no pedir FER comandos rutinarios. Admisión de sujetos sigue ceremonia humana autorizada, no modificación arbitraria de allowlist ni acceso de agente a credenciales. Sin gastos.

## Frontera con Archi: fixture automatizado

[Propuesta compartida](https://github.com/Montara-Projects/MONTARA-BRAIN/issues/32#issuecomment-7238461909). Banco sintético del piloto ya verificado, 702682 bytes totales (tres nombres fijos), copiar bajo UID pilot desde banco existente y volver a contrastar SHA256/tamaño antes de instalar root:montara-pilot 0750/0440, sin ejecutar FFmpeg ni render. Fuente:
- camera-a.mp4: 63410 B f290175c1fb7f2587baf6e535b0f6adde0ad78b2d31ec250ae027a0590abfbc7
- camera-b.mp4: 63194 B 2817a6ab4b4833f40a5eb9534a90c2c173d3affe408045594f54daa09d87674d
- master.wav: 576078 B 8ae3abdb2fef54830f15e0177af8daa92cfb8481564fc9822a9acee950eaf33e

Ruta candidata fija /opt/montara-pilot/fixture-bank-v1; confirmar con Archi contrato config explícita sólo DEVELOPMENT y ruta antes de activación. El banco no está colocado en originals por el helper ni se registra un UUID manualmente. Core único autorizador owner/project autenticado antes de FS, nombres y hashes del banco fijos, copia exclusiva no-follow bajo UID pilot, no overwrite, límite/tamaño, idempotencia y lock por proyecto, parciales sólo si existentes exactos, colisión/symlink rechazados. Core registra a través del contrato vigente, no DB directa, no media real ni FFmpeg pesado en HTTP. Archi implementa y prueba autorización, aislamiento, concurrencia/parcial y conflictos; Efrain prepara banco/runtime y release. No modificar archivos Archi. La PR presente es infra, no implementación Core. Pendiente confirmación Archi y asignación de Alfred.

## Evidencia focalizada

Rama efrain-002/v2-operaciones, base inicial c60a221a. Microgate Contabo UID montara-test (no root) job SHA256 74d6bd03a9f2d30b2e76e9dfd3c3236139d11e153fd580bd3db962d0c3b27653, EXIT0, **21/21 PASS** en 1.614 s (no benchmark). Blobs exactos verificados; pruebas de estado simulado y órdenes stop/start/restart, worker ocupado/failed/job pendiente, ACL JSON sintética, cierre y cierre no verificado, backup real sobre datos/SQLite sintéticos y rechazo DB inválida, symlink/hardlink externo/límite/retención, clasificador Bash exacto 12 casos, pines, política exacta sin comodines, syntax Bash/AST 3 bloques Python, delta YAML de ida/vuelta (única adaptación de owner root a UID de prueba). No probaron root efectivo, systemd real, sudoers efectivo, cierre edge, DB viva ni restauración. Primer microgate 15/15 era revisión previa; final sustituye. Cola #10 libre, informe conservado en workspace. Sin rerender ni suite histórica. Actions BRAIN verifica estructura; no confundir con microgate.

## Bootstrap único candidato, pendiente de revisión y de integración

Scripts exactos staged/readback en workspace Efrain, no ejecutar desde mutable workspace directamente como root. Candidato con pines del slot actual (4a7fb469 / wheel c7e11118). Tras Archi se deben fijar **pines de versión integrada** y contrato banco antes de entregar bloque final: si se modifica candidato, repetir sólo delta microgate y obtener GO Quasimodo. El siguiente loader demuestra forma única ya preparada; no usarlo ahora ni como segunda sesión aislada. No solicitar que FER inspeccione manualmente ni copie UUID. Un bloque final agrupará la preparación del banco, release/activación fixture coordinados, actualización launcher, delegación y checks de reconexión. Si el cambio de slot material exige una promoción, incluir su autorización y preflight específico; no confiar en un loader de slot anterior para nuevo slot.

```bash
# CANDIDATO — NO EJECUTAR antes de revisión, pines y autorización final.
sudo bash <<'SH'
set -Eeuo pipefail
umask 077
D=$(mktemp -d /root/montara-v2-ops.XXXXXXXX)
trap 'rm -rf -- "$D"' EXIT
while read -r name bytes digest; do
    runuser -u sentinelx -- head -c "$((bytes+1))" "/srv/montara-core/workspaces/efrain/v2-ops-$name" > "$D/$name"
    test "$(wc -c < "$D/$name")" = "$bytes"
    test "$(git hash-object --no-filters "$D/$name")" = "$digest"
done <<'PINS'
activate.sh 11209 dda73ea1753fb27379794209f723c47aca80dbc7
ops.py 18722 4d377f3f96227683ee357edbbdfc995dae3eacf9
worker-start.sh 2254 32936861f034b95d95a6a5479b10456799737676
montara-v2-ops.sh 280 2456351767d7a3356f18b30789fe691bf93d43de
sudoers 322 bc53e09a71130451fa2c93bf98be051b084f1609
PINS
/bin/bash "$D/activate.sh" install </dev/tty >/dev/tty 2>&1
SH
```

Gates de activación real (sin mutar antes): confirmación final de alta 4 sujetos y quiescencia/ausencia enrolador, aceptación QA/FER de permisos concretos; verificar snapshot de SentinelX strict/seven/disabled_ops, hashes de código, sudoers y preflight de root control files, estado/ACL/listeners/slot/config, banco fuente exacto, espacio y lock. No root aún por agente. Bootstrap prepara banco en root con copia limitada bajo UID pilot, no original/DB, guarda config/launcher previos en root privado, instala sólo helper/wrapper, reemplaza atómicamente launcher preservando grant anterior; sudoers cinco cadenas exactas, visudo -c, checks efectivos `sudo -l -U sentinelx` positivo/negativo shell/true/systemctl/restore/args extra/sin args; revoca y comprueba denegación de cinco verbos, reaplica y comprueba, YAML sólo añade una entrada; reinicia sólo SentinelX, verifica status real vía UID, no ejecutar stop/start/restart/backup en bootstrap. No cambiar HTTP/ingress/ACL/worker ni state para aplicar esta parte. Validación real de operación mutante pendiente de ventana autorizada tras revisión, preferir aprovechar mantenimiento fixture y backup necesario, no rerender. Cualquier divergencia STOP; revertir nueva delegación/allowlist/launcher previo por rollback, preservar banco/backup/estados. Si proceso activo durante revocación, grant se retira primero y se detiene la retirada de archivos hasta quiescencia; no matar proceso. No prometer rollback frente SIGKILL/caída. Revoke separado por operador autorizado `sudo /var/lib/montara-v2-ops/activate.sh revoke` retira sólo grant/entrada nueva/helper; mantiene corrección launcher y permiso worker anterior, datos y backups. Revocación no corta un comando ya iniciado. Tras OPS_LOCAL_READY=PASS, Efrain verifica reconexión y capabilities exactos (7 previos+1, disabled_ops/file_ops intactos), status saneado, negativos del wrapper sin ejecutar comandos privilegiados peligrosos, Alfred edge sin cambios. Si conexión falla, rollback/revisión en la misma sesión si viable; nunca usar otro host como puente. No afirmar PASS real hasta esas evidencias.

## Estado

Código candidato + pruebas y documentos, NO RUN root/host activo. Revocación real, ciclo de vida real, backup real, fixture Core, promoción material, recuperación/DR y Work pendientes. No despliegue ni permisos nuevos, no modificación V1/producto, ni gasto. Efrain coordina con Archi/Alfred; Quasimodo revisa delta y FER aprueba bloque final exacto.
