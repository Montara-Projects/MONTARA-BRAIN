# Misión 001 — Revisión del ADR candidato CORE V2

Fuente: [Montara #415](https://github.com/Montara-Projects/Montara/issues/415), última respuesta observada [JM, candidato consolidado](https://github.com/Montara-Projects/Montara/issues/415#issuecomment-7141340666). Volver a consultar antes de trabajar.

FER orquesta. Cada especialista activo lee íntegramente el issue y referencias pertinentes, identifica acuerdos, propuestas, experimentos y bloqueos, y propone tareas propias con dependencias, evidencia y criterios de aceptación. Puede realizar investigación de solo lectura y registrar propuestas en BRAIN. No asignarse implementación, recursos, compras, cambios de runtime ni MAIN sin autorización de FER y acuerdos compartidos pertinentes.

Archi: dominio, contratos, cardinalidades, ownership y consolidación de interpretaciones.
Efrain: release/installer, capacidad, aislamiento, reproducibilidad, rollback y costes.
Eugenia: DAG, scheduler, representaciones, Engine/Mixer, reutilización y benchmarks.
Compi: contratos locales, autenticación, compatibilidad, aislamiento, Windows/Mac y calidad.
Quasimodo: gates, criterios de aceptación, regresión, fallos, seguridad y QA diferencial.

Cada informe enlaza comentarios exactos, identifica desacuerdos y propone tareas sin duplicar issues existentes. FER resuelve solapamientos y asigna trabajo. Work/Codex realizan revisión independiente; doble ACK de propietarios antes de freeze y autorización separada de implementación/recursos. No convertir fecha provisional del 24/12 en compromiso.

Estado inicial: candidato recibido, revisión independiente y doble ACK pendientes. No enviar respuesta al #415 por esta misión sin autorización.

## Regla de cierre práctico
Una sola ronda por especialista, máximo cinco hallazgos accionables. Clasificar: BLOQUEANTE (impide el slice o vulnera un invariante), NECESARIO (tarea del slice), DIFERIBLE (backlog). Si no hay bloqueo, declarar ACK técnico sin inventar mejoras. No reabrir acuerdos sin evidencia material. Archi consolida duplicidades; FER decide y Work/Codex revisan una vez el candidato. Solo nuevas evidencias materiales justifican otra ronda. Priorizar un slice real y ajustar arquitectura con resultados, no perfección teórica.
