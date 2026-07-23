---
description: Tomar una tarea de Plane — la próxima más urgente o un numero dado — y resolverla de punta a punta (In Progress → implementar → Testing/Done)
allowed-tools: Bash(bash:*)
argument-hint: "[#seq — vacío = la próxima más urgente de Todo]"
---

Tarea a tomar (si se pasó un `#seq` es su detalle; si no, la próxima más urgente de Todo):

!`bash "${CLAUDE_PROJECT_DIR:-.}/.claude/scripts/plane.sh" ${ARGUMENTS:+get} ${ARGUMENTS:-next}`

Ejecutá el **ciclo agéntico completo** sobre esa tarea (skill `plane-tracking` § *Ciclo de vida
agéntico* + flujo "Trabaja la tarea" de `CLAUDE.md`). Resumen operativo:

1. **Sin tarea** (`(sin tareas en estado 'Todo')`): reportalo y sugerí `plane.sh list --state
   Backlog` para ver qué se puede promover a Todo. Fin.
2. **Leé el issue completo** (objetivo, CA, módulos, cómo validar). Si la descripción **no alcanza
   para arrancar** (ambigua, sin criterios): preguntá lo mínimo al usuario, `update` del issue con
   lo aclarado, y recién después seguí.
3. **Arrancá**: `plane.sh move <#seq> "In Progress"`.
4. **Rama de integración**: se trabaja directo sobre la rama de integración del repo (típ.
   `develop_19.0`) — modelo directo, sin ramas de feature/fix ni PR (ver skill `git`). @git-ops
   (a pedido) confirma que el repo esté parado ahí.
5. **Resolvé** con el flujo que corresponda de `CLAUDE.md` (Implementa / Modifica / Crea módulo /
   Refina / Migra), con todas sus precondiciones (docs, SDD, tests, review). Comentá en el issue
   los hitos relevantes (decisiones, bloqueos).
6. **Cerrá el ciclo**:
   - Implementado y validado → `move <#seq> "Testing"` + `comment` (rama, módulos+versión, qué
     validar y dónde). Si el usuario ya verificó → `move <#seq> "Done"`.
   - Bloqueado / falta input → `comment` con el bloqueo concreto y reportá al usuario (la tarea
     queda en In Progress, o vuelve a Todo si no se empezó nada).
7. **Reportá** al usuario: qué issue se trabajó, rama de integración, estado final en Plane, y el
   handoff Git (commit/push directo solo a pedido).
