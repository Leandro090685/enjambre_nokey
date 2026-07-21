# Enjambre Nokey — Odoo (Claude Code)

Sistema de agentes, skills y hooks para desarrollo Odoo con **Claude Code**, **agnóstico de la
versión de Odoo**.

## 📦 Qué es

Un enjambre de subagentes especializados coordinados por un orquestador (`CLAUDE.md`), con
conocimiento cargable (skills), comandos rápidos y validación automática de convenciones del proyecto y
breaking changes de la versión de Odoo objetivo.

El repo **es** la carpeta `.claude/` del workspace (agents, skills, commands, hooks, references,
assets, `CLAUDE.md`, `AGENTS.md`, `workspace.md`). En la raíz del workspace, `CLAUDE.md` y
`AGENTS.md` son **symlinks** a los de `.claude/`. El detalle completo de la estructura está en
**[ENJAMBRE.md](ENJAMBRE.md)**.

## 🧭 Tres fuentes de verdad (no duplicar)

El enjambre se apoya en tres fuentes únicas; todo lo demás (skills, agents, commands, hooks) las
**referencia** sin duplicar:

- **Entorno** (por dev) → `.claude/workspace.md` (`ODOO_VERSION`, paths, clientes, Docker/venv)
- **Convenciones del proyecto** → `.claude/AGENTS.md` (código) + `CLAUDE.md` (orquestación)
- **Conocimiento por versión** → `.claude/references/` (breaking changes + datos del hook)

Detalle y diagrama en **[ENJAMBRE.md](ENJAMBRE.md)**.

## 🚀 Instalación

Ver **[CLAUDE_SETUP.md](CLAUDE_SETUP.md)** para el paso a paso. En resumen: cloná este repo como
`<workspace>/.claude`, creá los symlinks `CLAUDE.md` y `AGENTS.md` en la raíz, copiá
`workspace.example.md` → `workspace.md` y completalo con tu entorno, y abrí `claude`.

## 🧠 Documentación

- **[ENJAMBRE.md](ENJAMBRE.md)** — Arquitectura completa explicada para humanos
- **[CLAUDE_SETUP.md](CLAUDE_SETUP.md)** — Instalación y detalles de configuración
- **[AGENTS.md](AGENTS.md)** — Convenciones que todo agente debe respetar
- **`.claude/skills/`** — Skills de conocimiento (ORM, vistas, seguridad, etc.)

## ⚙️ Mantenimiento

### Agregar un nuevo agente

Crear `.claude/agents/<nombre>.md` con frontmatter:

```yaml
---
name: nombre-del-agente
description: Qué hace y cuándo invocarlo
tools: Read, Edit, Write, Bash, Grep, Glob
---
```

Si es un procedimiento interno (solo invocado por el orquestador), indicarlo en la `description` y agregarlo en `CLAUDE.md`.

### Agregar un nuevo skill

Crear `.claude/skills/<nombre>/SKILL.md` con frontmatter:

```yaml
---
name: nombre-del-skill
description: Cuándo usarlo
---
```

### Soportar una versión nueva de Odoo

1. Agregar `.claude/references/{N-1}_to_{N}.md` (salto de migración).
2. Agregar `.claude/references/v{N}_gotchas.md` (gotchas curados).
3. Agregar `.claude/references/patterns/v{N}.patterns` (patrones del hook).
4. Cada dev pone `ODOO_VERSION: {N}` en su `workspace.md`.

No hay que tocar agentes, skills, hooks ni docs: son agnósticos de versión.

---

*Nokey — Sunra*
