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

## Propuesta organizativa de FER para la respuesta conjunta a JM (25/11/2026)
Pendiente de comunicar y consensuar con JM: durante la etapa inicial de CORE V2, proponer que JM lidere el mantenimiento de MAIN V1 y sus LAB, incluyendo mejoras compatibles que no alteren contratos ni arquitectura compartida. FER y sus especialistas concentrarán el esfuerzo en construir y estabilizar CORE V2 aislado y en consolidar el piloto BRAIN. Coordinar P0, dependencias compartidas, reutilización de componentes y cambios transversales; no implica transferir unilateralmente permisos, ownership ni autorización de despliegue. Invitar a JM a participar en BRAIN cuando la metodología esté madura y ambos lo acuerden; no restringir su acceso actual a la organización ni al producto. Incorporar esta propuesta a la respuesta final de FER a Montara #415, tras la revisión prevista, sin publicarla allí todavía.

## Primer checkpoint del piloto
Archi-001 y Eugenia-001 completaron una ronda con ACK técnico y cero bloqueantes; informes y relevos en sus rutas individuales. No repetir su revisión. Pendiente completar perspectivas restantes y auditoría independiente, consolidar propuestas y obtener acuerdos humanos. Sin implementación autorizada.
