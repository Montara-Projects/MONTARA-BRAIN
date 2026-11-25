# Work-001 — dictamen independiente de CORE V2

Fecha de recepción: 2026-11-25. Fuente: informe entregado por Work a FER y facilitado íntegramente en la conversación de coordinación. Esta es una síntesis documental, no una segunda auditoría ni una reproducción verificada del archivo de Biblioteca.

**GO arquitectónico para doble ACK FER/JM. Cero bloqueantes identificados.** Desarrollo condicionado a encargo FER y aprobación de entorno, límites y presupuesto. MAIN y migración quedan fuera de esta autorización.

## Hallazgos
1. NECESARIO — Efrain: aislamiento efectivo de VM compartida, incluyendo disco temporal, IO, apagado, sesiones, datos, sockets, credenciales y permisos de cuenta de servicio adjunta si existe. Si no es demostrable, proponer Linux independiente. PR #408 sigue en borrador.
2. NECESARIO — Archi/Eugenia: cancelación y publicación ligadas al intento exacto; la ruta de cierre V1 consultada selecciona worker por owner/proyecto sin generación objetivo. Verificar fencing, revocación, reconciliación, respuesta perdida, cancelación tardía, reinicio y cuota única. [Ledger](https://github.com/Montara-Projects/Montara/blob/7113fd2801558cc31bf9b2c1bfab360c7faa40ca/urano/job_recovery_ledger.py#L109-L152), [ruta de cierre](https://github.com/Montara-Projects/Montara/blob/7113fd2801558cc31bf9b2c1bfab360c7faa40ca/urano/private_broker_service.py#L262-L274).
3. NECESARIO — Quasimodo/Eugenia/JM: aceptación del slice Linux con cloud off, fixture sintético, OIDC real aislado, proyecto, receta versionada, motor real, MP4 decodificable con calidad conocida, reapertura tras reinicio, controles negativos entre owners, conflicto save y rechazo proxy insuficiente HQ. Companion Win/Mac tiene gate separado.
4. NECESARIO — Efrain/Quasimodo: fuentes, dependencias y toolchain fijados; dos árboles de contenido comparados, hash del paquete exacto, worker desde paquete, segunda instalación y recuperación preservando escrituras nuevas; forward-fix probado si rollback incompatible. [#293](https://github.com/Montara-Projects/Montara/issues/293), [#392](https://github.com/Montara-Projects/Montara/issues/392).
5. DIFERIBLE — paridad completa, optimización, cloud real, segundo proveedor y DR integral. Baseline Colibrí V1 y A/B comparable posterior.

## Orden recomendado
Tras doble ACK y encargo: Archi contrato único v0; Efrain destino/empaquetado; JM y Quasimodo fixture y calidad; Eugenia integración motor; Quasimodo verificación del paquete; Compi contribuye al contrato y valida desktop después del slice Linux.

Auditoría de solo lectura. Capacidad, runtime efectivo y ejecución V2 no certificados. Referencias: [Montara #415](https://github.com/Montara-Projects/Montara/issues/415), [ADR candidato](https://github.com/Montara-Projects/Montara/issues/415#issuecomment-7141340666), [BRAIN #1](https://github.com/Montara-Projects/MONTARA-BRAIN/issues/1).
