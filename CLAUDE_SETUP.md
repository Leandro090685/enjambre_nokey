# Enjambre Nokey — Setup para Claude Code

Sistema de agentes, skills y hooks para desarrollo Odoo con **Claude Code**, agnóstico de la
versión de Odoo (la versión se define por desarrollador en `workspace.md`).

## 📦 Qué incluye

El repo es la carpeta `.claude/` del workspace: `agents/` (11 subagentes), `skills/` (14),
`commands/` (9), `hooks/` (validación automática data-driven), `references/` (breaking changes por
versión), `assets/` (template HTML + plantillas de test/política de repo), `CLAUDE.md` (orquestador),
`AGENTS.md` (convenciones) y `workspace.md` (entorno por dev, gitignored).

> Estructura detallada y diagrama: **[ENJAMBRE.md](ENJAMBRE.md)**.

## 🚀 Instalación

El repo **es** la carpeta `.claude` del workspace. Se clona ahí y se enlazan `CLAUDE.md` y
`AGENTS.md` a la raíz del workspace (donde Claude Code los carga junto a `.claude/`).

```bash
# 1. Ir al workspace de Odoo (cualquier versión)
cd <WORKSPACE_ROOT>          # ej: ~/repos/19, ~/repos/17, ...

# 2. Clonar este repo COMO la carpeta .claude
git clone <repo-url> .claude

# 3. Symlinkear el orquestador y las convenciones a la raíz del workspace
ln -sf .claude/CLAUDE.md CLAUDE.md
ln -sf .claude/AGENTS.md AGENTS.md

# 4. Crear tu config de entorno (NO se commitea)
cp .claude/workspace.example.md .claude/workspace.md
$EDITOR .claude/workspace.md   # completar ODOO_VERSION, paths, Docker, DB, cliente

# 5. Permisos de ejecución de los hooks
chmod +x .claude/hooks/*.sh

# 6. Abrir Claude Code en el workspace
claude
```

### Resultado final

```
<WORKSPACE_ROOT>/
├── CLAUDE.md              → symlink a .claude/CLAUDE.md (auto-cargado por Claude Code)
├── AGENTS.md              → symlink a .claude/AGENTS.md
├── odoo/                  ← Odoo core (no modificar)
├── enterprise/            ← Odoo Enterprise (no modificar)
├── <tus-addons>/          ← Módulos custom (donde los tengas; ver workspace.md)
└── .claude/              ← El enjambre (este repo): settings, workspace.md, agents, skills, ...
```

> Describí en `workspace.md` dónde viven tus addons custom (y opcionalmente declará `ADDONS_ROOTS`).

## 🌎 Configuración de entorno (`workspace.md`)

`workspace.md` es la **única fuente de verdad del entorno**, por desarrollador y gitignored.
Describe en prosa cómo está armado el workspace: versión de Odoo (`ODOO_VERSION`), paths (root,
`odoo/`, `enterprise/`, addons), cómo están organizados los clientes, y si Odoo corre en Docker o
venv. Ningún agente/skill/hook hardcodea paths ni versión: todos resuelven desde aquí. Los detalles
puntuales (contenedor Docker, base de datos) se resuelven en runtime. Ver `workspace.example.md`.

## 🧩 Cómo funciona y cómo se extiende

La arquitectura completa (agentes y sus tools, skills, el hook de validación paso a paso, el flujo
del orquestador) está explicada en **[ENJAMBRE.md](ENJAMBRE.md)**. Cómo agregar un agente/skill o
**soportar una versión nueva de Odoo** está en **[README.md](README.md) → Mantenimiento**.

En resumen, para soportar una versión nueva basta con agregar en `references/` los archivos
`{N-1}_to_{N}.md`, `v{N}_gotchas.md` y `patterns/v{N}.patterns`, y poner `ODOO_VERSION: {N}` en tu
`workspace.md`. No se tocan agentes, skills, hooks ni docs (son agnósticos de versión).

---

*Nokey — Sunra*
