---
description: Operar el seguimiento del proyecto en Plane.so (list/get/create/update/move/comment)
allowed-tools: Bash(bash:*)
argument-hint: "[list | next | states | get <#> | move <#> \"<Estado>\" | comment <#> \"...\" | create --name ...]"
---

Estado del seguimiento en Plane:

!`bash "${CLAUDE_PROJECT_DIR:-.}/.claude/scripts/plane.sh" ${ARGUMENTS:-list}`

Si no se pasaron argumentos se listaron los issues. Con argumentos se ejecutó ese subcomando de
`plane.sh` (ver skill `plane-tracking` para el modelo de estados y la disciplina de sync).

- `move`/`comment`/`create`/`update` se ejecutan directo (política agéntica — ver skill
  `plane-tracking`: se **informa después**, no se pide antes). Solo `delete` exige OK explícito.
- Para **tomar y resolver** una tarea (no solo consultarla), usá `/tarea` — ese comando ejecuta el
  ciclo completo (In Progress → resolver → Testing/Done).
- Si un subcomando con comillas/espacios no se parseó bien desde acá, corré `plane.sh` directamente
  con la tool Bash (mismo script), respetando el quoting.
- No inventes tareas ni estados: si algo no existe, `plane.sh` lista lo válido.
