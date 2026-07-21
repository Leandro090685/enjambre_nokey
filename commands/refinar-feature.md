---
description: Refinar un requerimiento de desarrollo nuevo (idea cruda, pre-spec) para la planning
---

Refiná el requerimiento de $ARGUMENTS (idea cruda, puede ser un `.docx` con imágenes), siguiendo el
flujo "Refina requerimiento" (pre-spec, read-only en cuanto al análisis).

Invocá a @feature-analyst con la idea cruda + el contexto disponible para que evalúe contra Odoo
core/customizaciones, ancle los `path:L#` que necesite, cuestione solo si hace falta, proponga
alternativas y devuelva el **refinamiento completo para la planning** (decisiones, CA refinados,
breakdown de tareas, sanity-check de estimación).

Cuando devuelva, **vos (orquestador) escribís** ese markdown en
`especificaciones_funcionales/<mismo nombre del insumo>.md` (misma carpeta y nombre que el `.docx`,
extensión `.md`). Si hay varios insumos/versiones, tomá la más actual como base y dejá notada la
divergencia. Reportá al usuario la ruta del `.md` + un resumen.

(Opcional) Si el requerimiento toca un módulo de cliente, podés correr antes @client-context; si
además hace falta anclar el core más allá de lo que el analista pueda verificar, @researcher. Ambos
son read-only e independientes: lanzalos en paralelo si los dos aplican.

@feature-analyst es **read-only**: nunca escribe archivos (el `.md` lo materializás vos). Si tras la
planning se decide avanzar, el siguiente paso (manual) es el flujo "Especifica feature" con
@sdd-generate.
