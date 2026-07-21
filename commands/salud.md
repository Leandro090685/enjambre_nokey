---
description: Chequear la salud del entorno del enjambre (workspace.md, version, paths, references, Docker, git)
allowed-tools: Bash(bash:*)
---

Diagnóstico del entorno:

!`bash "${CLAUDE_PROJECT_DIR:-.}/.claude/scripts/salud.sh"`

Si todo está [OK], decilo en una línea. Si hay [WARN] o [FAIL], listá cada uno con el **fix concreto**
(el comando o el cambio en `workspace.md` que lo resuelve), priorizando los [FAIL] (bloquean el
funcionamiento correcto del enjambre). No inventes problemas que el chequeo no reportó.
