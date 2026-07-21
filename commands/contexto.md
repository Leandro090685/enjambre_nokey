---
description: Mostrar un resumen de orientacion del workspace (version Odoo, cliente/DB, Docker, git, modulo actual y specs)
allowed-tools: Bash(bash:*)
---

Contexto actual del workspace:

!`bash "${CLAUDE_PROJECT_DIR:-.}/.claude/scripts/contexto.sh"`

Resumí en 2-3 líneas dónde está parado el desarrollador (versión de Odoo, cliente/módulo actual,
estado de git y de Docker) y, si detectás algo que requiera atención (drift de versión spec↔manifest,
Docker caído, cambios sin commitear), señalalo. Usá este contexto para orientar el resto de la sesión.
