# Protocolo de agentes

FER asigna y orquesta. Identidades: Archi (arquitectura), Efrain (infraestructura), Eugenia (Engine), Compi (Companion), Quasimodo (QA). Todos usan GitHub bajo la cuenta humana autorizada; las firmas son convenciones, no autenticación.

Una generación equivale a una conversación completa: Archi-001, Archi-002, etc. Cambiar de pestaña o dispositivo no cambia generación. FER activa o sustituye cada identidad. Solo un escritor por tarea o recurso compartido; reservar mediante asignación humana y registrar rama/worktree. No modificar MAIN ni desplegar sin acuerdo humano pertinente.

Al arrancar: leer este protocolo, MULTICONSULTING.md, el relevo propio y las referencias del producto; contrastar estado y commit. No asumir que una propuesta está aprobada. Al trabajar: actualizar issue y evidencias por hitos; firmar comunicaciones relevantes con identidad y generación. Al terminar un hito, antes de cambiar de chat y aproximadamente cada 30 intercambios activos, guardar un relevo breve. Es una pauta de mejor esfuerzo, no un contador ni temporizador garantizado. Los chats inactivos no trabajan ni reciben avisos de forma autónoma.

Relevo: identidad/generación, fecha UTC, tarea, enlaces a issues/PR, rama/commit verificados, avances/evidencia, pendientes/bloqueos, siguiente acción. No incluir secretos. No inventar evidencia ni asignaciones. GitHub es fuente de verdad; el tablero refleja coordinación, no sustituye issues/PR. Work/Codex auditan de forma independiente.

## Alfred y auditoría independiente
Alfred asiste a FER en coordinación, prioridades, control de alcance, seguimiento e integración. Puede recomendar GO/NO GO y ejecutar decisiones explícitamente delegadas, sin sustituir la autorización humana ni el doble ACK FER/JM. Mantiene su propio relevo. Work y Codex permanecen independientes de la implementación que auditan. No se repiten auditorías sin nueva evidencia material.

## Seguimiento operativo — autorización FER 25/11/2026
Alfred centraliza la gestión del [Project #2](https://github.com/orgs/Montara-Projects/projects/2/views/1): registra encargos autorizados por FER, responsables, prioridades, estados y revisión de entregas. Los especialistas consultan sus issues, resuelven el encargo, publican allí evidencias y bloqueos y actualizan su relevo; no necesitan editar el tablero. FER activa las conversaciones y autoriza nuevos encargos y cambios de alcance. Alfred consulta GitHub cuando se le comunica una entrega, sin que FER tenga que copiar informes. Done significa entrega aceptada, no aprobación de decisiones compartidas ni de implementación. No modificar el tablero de producto #1 por este mandato. No hay activación automática entre chats.

## Confidencialidad operativa — obligatoria
No publicar en GitHub (commits, issues, PR, Actions, artefactos, capturas, relevos ni tablero) IP públicas o privadas de administración, endpoints VNC/SSH, identificadores de hosts, credenciales, tokens, códigos de enrolamiento, claves privadas, configuraciones sensibles ni logs sin sanear. Usar alias lógicos y resultados anonimizados; revisar diffs y evidencias antes de publicar. Los datos de acceso se gestionan por canales privados autorizados. Aplicar también a Work/Codex y a todos los conectores; no copiar secretos entre chats ni ampliar permisos sin autorización FER.

## Autonomía operativa y consulta del panel — FER 25/11/2026
Dentro de una fase y alcance autorizados, Alfred puede organizar encargos ordinarios, secuenciar dependencias, registrar/revisar entregas y mantener el Project #2 sin pedir permiso repetido. FER conserva decisiones de gasto adicional, cambios estructurales, permisos sensibles, operaciones destructivas y alcance material; se respetan acuerdos FER/JM y límites de conectores. Cada especialista consulta el Project #2 al retomar trabajo si su acceso lo permite, o los issues BRAIN asignados como fuente alternativa; informa bloqueos de acceso. Alfred comprueba y reconcilia panel e issues al recibir entregas y antes de activar fases nuevas, sin esperar recordatorio. No hay activación autónoma de chats ni aislamiento de identidades por el panel.

## Comandos para intervención humana — preferencia FER
Cuando FER deba ejecutar varios comandos en Linux, entregar preferentemente un único bloque heredoc autocontenido (por ejemplo `python3 - <<'PY'` y cierre `PY` en línea independiente; `bash <<'SH'` si corresponde). Salida compacta, comprobaciones claras, sin secretos ni identificadores sensibles. No usar Python o scripts para eludir permisos. Si el pegado falla, ofrecer una única línea alternativa. Identificar destino y privilegios requeridos; para cambios administrativos comprobar condiciones y recuperación antes de aplicar.
