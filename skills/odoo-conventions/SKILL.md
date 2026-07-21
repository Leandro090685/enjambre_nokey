---
name: odoo-conventions
description: Convenciones del proyecto y breaking changes de Odoo (version agnostica). Cargar siempre al trabajar en este workspace. Indexa las fuentes unicas de verdad — entorno (workspace.md), convenciones (AGENTS.md) y breaking changes por version (references/).
---

# Convenciones del proyecto para Odoo

Este skill es un **índice**: no duplica contenido, apunta a las **fuentes únicas de verdad**.
Cargalo al inicio de cualquier sesión y consultá la fuente que corresponda.

## 1. Entorno → `.claude/workspace.md`

Cómo está armado el workspace: versión de Odoo (`ODOO_VERSION`), paths (root, `odoo/`,
`enterprise/`, addons), cómo están organizados los clientes, y si Odoo corre en Docker o venv.
**Nada de esto se hardcodea** en agentes/skills/docs: sale de ahí (los detalles puntuales como el
contenedor o la DB se resuelven en runtime). Si no existe, copialo de `.claude/workspace.example.md`.

## 2. Convenciones de código → `.claude/AGENTS.md`

Fuente única de:
- Identidad del proyecto, licencia LGPL-3, rutas estándar del workspace.
- Idioma (código en inglés, comentarios en español, UI con `_()` en inglés).
- Encabezados/pies obligatorios (Python y XML) + vim modelines.
- Plantillas canónicas de `__manifest__.py`, modelo y vista.
- Arquitectura/prácticas (preferir `_inherit`+`super()`, evitar `sudo()`, ACLs, N+1).
- Regla de documentación obligatoria (`README.md` + `static/description/index.html`).

## 3. Breaking changes → `.claude/references/`

Por tu `ODOO_VERSION` (de `workspace.md`):
- `references/{ODOO_VERSION-1}_to_{ODOO_VERSION}.md` — salto de migración paso a paso.
- `references/v{ODOO_VERSION}_gotchas.md` — gotchas curados (constraints, `res.groups`,
  `res.users`, `hr.contract`/`hr.version`, `hr.leave`, vistas `<list>`, ORM, etc.).
- `references/common_patterns.md` — patrones comunes entre versiones.

El hook `check_breaking_changes.sh` valida automáticamente los patrones prohibidos de la versión
(`references/patterns/v{ODOO_VERSION}.patterns`) y **bloquea** el Write/Edit si los encuentra.

## Subagentes y skills

La tabla de subagentes y cuándo invocarlos vive en `CLAUDE.md` (orquestador). Skills de patrones
específicos: `odoo-orm-patterns`, `odoo-views`, `odoo-security`, `odoo-wizards`, `odoo-qweb-reports`,
`debugging-odoo`, `git`, `sdd-specification`.
