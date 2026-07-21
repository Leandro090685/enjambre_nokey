# 🧬 El Enjambre Nokey — Arquitectura (Odoo, version-agnostic)

> Documentación para humanos. Explica cómo funciona el sistema de agentes, skills y hooks que
> automatizan el desarrollo Odoo con **Claude Code**. El enjambre es **agnóstico de la
> versión de Odoo**: la versión objetivo se define por desarrollador en `.claude/workspace.md`.

---

## 🎯 Filosofía

El enjambre es un sistema de **agentes especializados** que trabajan juntos bajo la coordinación de un **orquestador**. Cada agente hace una sola cosa y la hace bien. Ningún agente le habla a otro directamente — toda la comunicación pasa por el orquestador.

**Principios:**
- **Entorno único**: el entorno (versión, paths, Docker, DB, cliente) se define una sola vez en `workspace.md`; nada se hardcodea
- **Spec-first**: para features complejas, primero se escribe una especificación, después el código
- **Documentación obligatoria**: ningún módulo se toca sin `README.md` + `index.html`
- **Validación automática**: cada archivo que se escribe se valida al instante contra convenciones del proyecto y breaking changes de la versión objetivo
- **Convenciones estrictas**: headers, vim modelines, idioma (código en inglés, comentarios en español), licencia LGPL-3

---

## 🧭 Tres fuentes de verdad (no se duplican)

| Capa | Fuente única | Contenido |
|------|--------------|-----------|
| **Entorno** (por dev) | `.claude/workspace.md` | `ODOO_VERSION`, paths (root/odoo/enterprise), organización de clientes, Docker o venv |
| **Convenciones del proyecto** | `.claude/AGENTS.md` + `CLAUDE.md` | headers, manifest, licencia, orquestación, fallback |
| **Conocimiento por versión** | `.claude/references/` | breaking changes (docs + datos del hook) |

Todo lo demás (skills, agents, commands, hooks) **referencia** estas tres capas.

---

## 🗂️ Estructura de archivos

```
<WORKSPACE_ROOT>/                       ← definido en workspace.md (ej. ~/repos/19)
├── CLAUDE.md                           → symlink a .claude/CLAUDE.md (auto-cargado + importa AGENTS.md)
├── AGENTS.md                           → symlink a .claude/AGENTS.md (convenciones globales)
│
└── .claude/                            ← este repo, clonado aquí
    ├── settings.json                   ← Permisos + hook PostToolUse (validación automática)
    ├── workspace.example.md            ← Plantilla de entorno
    ├── workspace.md                    ← Config de entorno POR DEV (gitignored)
    │                                     (secretos per-dev: archivo local FUERA del repo, NOKEY_SECRETS_FILE)
    │
    ├── agents/                         ← Agentes especializados (11)
    │   ├── client-context.md           ← Contexto de cliente/DB
    │   ├── feature-analyst.md          ← Refina idea cruda (pre-spec) para la planning → .md [read-only]
    │   ├── researcher.md               ← Investigación read-only en core/enterprise
    │   ├── code-dev.md                 ← Desarrollo (modelos, vistas, wizards)
    │   ├── scaffold.md                 ← Estructura base de módulos nuevos
    │   ├── reviewer.md                 ← Code review con checklist
    │   ├── testing.md                  ← Testing estático/funcional/upgrade
    │   ├── git-flow.md                 ← Operaciones Git genéricas: ramas, commits, PR
    │   ├── odoo-migration.md           ← Migración entre versiones [procedimiento interno]
    │   ├── module-index-html.md        ← Documentación HTML [procedimiento interno]
    │   └── sdd-generate.md             ← Especificaciones SDD [procedimiento interno]
    │
    ├── skills/                         ← Conocimiento cargable bajo demanda (14)
    │   ├── odoo-conventions/SKILL.md   ← Índice de convenciones + breaking changes (puntero)
    │   ├── odoo-orm-patterns/SKILL.md  ← Patrones ORM
    │   ├── odoo-views/SKILL.md         ← Patrones de vistas
    │   ├── odoo-security/SKILL.md      ← Patrones de seguridad
    │   ├── odoo-qweb-reports/SKILL.md  ← Patrones de reportes QWeb
    │   ├── odoo-wizards/SKILL.md       ← Patrones de wizards
    │   ├── odoo-controllers/SKILL.md   ← Patrones de controllers / portal web
    │   ├── odoo-api-integration/SKILL.md ← Integración con APIs externas (REST/JSON/XML-RPC)
    │   ├── odoo-data-migration/SKILL.md ← Migración de datos / scripts de upgrade
    │   ├── odoo-tests/SKILL.md         ← Patrones de tests (si se piden o el repo los requiere)
    │   ├── debugging-odoo/SKILL.md     ← Técnicas de debugging
    │   ├── git/SKILL.md                ← Flujo Git (staging/prod Odoo.sh, release, hotfix)
    │   ├── plane-tracking/SKILL.md     ← Seguimiento en Plane.so (ciclo agéntico de tareas)
    │   ├── sdd-specification/SKILL.md  ← Metodología SDD
    │   └── minimal-footprint/SKILL.md  ← Disciplina anti-over-engineering (escalera + NO-negociables)
    │
    ├── commands/                       ← Slash commands (11)
    │   ├── odoo-module.md  odoo-model.md  odoo-view.md  odoo-inherit.md
    │   ├── analizar-core.md  analizar-enterprise.md  refinar-feature.md
    │   ├── contexto.md  salud.md
    │   └── plane.md  tarea.md          ← Seguimiento Plane + tomar/resolver tareas
    │
    ├── hooks/                          ← Validación + automatización (los cablea settings.json)
    │   ├── post_write.sh               ← Dispatcher PostToolUse (lee el JSON del evento)
    │   ├── validate_files.sh           ← Headers, sintaxis, manifiesto, docs (no bloquea)
    │   ├── check_breaking_changes.sh   ← Patrones prohibidos según ODOO_VERSION (bloquea, data-driven)
    │   ├── protect_core.sh             ← PreToolUse: impide escribir en odoo/ y enterprise/
    │   ├── session_pull.sh             ← SessionStart: auto-update seguro del enjambre
    │   ├── session_orient.sh           ← SessionStart: banner de orientación
    │   ├── mark_prompt.sh              ← UserPromptSubmit: marca inicio (umbral de notificación)
    │   ├── on_notification.sh          ← Notification: 🔐 permiso / ⏸ esperando input (por type)
    │   ├── on_stop.sh                  ← Stop: ✅ turno completo / ⌛ esperando respuesta (+extracto)
    │   ├── on_subagent_stop.sh         ← SubagentStop: 🔁 etapa terminada (agente + Status envelope)
    │   ├── notify.sh                   ← Notificador portable (macOS/WSL/Linux/bell)
    │   └── lib.sh                      ← Librería compartida (sourced)
    │
    ├── scripts/                        ← Capa determinista on-demand (agentes/orquestador la invocan)
    │   ├── contexto.sh  salud.sh       ← Backends de /contexto y /salud
    │   ├── odoo_runtime.sh             ← Runtime Odoo (logs/upgrade/psql/backup/validate) → @testing
    │   ├── cliente.sh                  ← Inventario de cliente (módulos, SDD, drift) → @client-context
    │   ├── git_state.sh                ← Estado Git básico (rama, protegida, staged, módulos) → @git-flow
    │   ├── extract_docx.sh             ← Ingesta .docx (texto+imágenes) → @feature-analyst
    │   ├── spec_lint.py                ← Linter de specs SDD → @sdd-generate y pre-pass de analyze
    │   ├── review_static.sh            ← Pre-pass estático de review (módulo completo) → @reviewer (vía orquestador)
    │   ├── plane.sh  plane_api.py      ← Cliente Plane.so (list/next/get/create/update/move/comment) → orquestador
    │   └── statusline.sh               ← Línea de estado
    │
    ├── references/                     ← Breaking changes por versión (archivos reales)
    │   ├── {N-1}_to_{N}.md             ← Salto de migración (13_to_14 … 18_to_19)
    │   ├── v{N}_gotchas.md             ← Gotchas curados (ej. v19_gotchas.md)
    │   ├── common_patterns.md
    │   └── patterns/v{N}.patterns      ← Datos que consume el hook
    │
    └── assets/
        ├── index-template-v19.html     ← Template HTML para documentación de módulos
        └── templates/                  ← swarm.conf.tmpl (política de tests por repo)
                                          + functional_test.py.tmpl (plantilla de test funcional, @testing)
```

---

## 🧠 Cómo funciona — explicación paso a paso

### 1. Arranque

Claude Code lee la configuración del workspace. Esto carga:

| Qué | Desde dónde | Efecto |
|-----|-------------|--------|
| **Entorno** | `.claude/workspace.md` | Versión, paths, Docker, DB, cliente, `NOKEY_SECRETS_FILE` — leído por agentes/skills/hooks |
| **Orquestador + convenciones** | `CLAUDE.md` (importa `AGENTS.md` con `@AGENTS.md`) | Siempre en contexto del agente principal |
| **Permisos + hook** | `.claude/settings.json` | Permisos de tools y validación tras cada write/edit |
| **Agentes** | `.claude/agents/` | Subagentes invocables con la tool `Task` |
| **Skills** | `.claude/skills/` | Disponibles para cargar con la tool `Skill` |
| **Commands** | `.claude/commands/` | Atajos: `/odoo-module`, `/odoo-model`, etc. |

### 2. El orquestador (agente principal)

Es el **único agente que le habla al usuario**. Recibe el request, decide qué subagentes invocar, integra resultados, y reporta.

**No escribe código.** Su trabajo es coordinar.

Su comportamiento está definido en `CLAUDE.md`:
- Tabla de 11 subagentes con cuándo invocar cada uno
- Flujos típicos (`Migra`, `Revisa`, `Crea módulo`, `Refina` (planning), `Especifica`, `Implementa`, `Modifica`, `Trabaja la tarea` (Plane, `/tarea`), `Git`)
- Reglas de orquestación (la primera: leer `workspace.md`)
- Protocolo de fallback (máx 2 intentos por agente)
- Formato de handoff estandarizado entre agentes

#### Paralelización por niveles (`PARALLELISM` en `workspace.md`)

Cuánto paraleliza el orquestador es **configurable por dev** (jul-2026; antes regía un absoluto
"un agente a la vez para escrituras" sin rationale registrado). Tres niveles: `off` (todo
secuencial), `readonly` (**default**: solo subagentes read-only e independientes en datos, en
cualquier flujo) y `full` (además pares de fase segura y escritores entre repos distintos). La
matriz operativa vive en `CLAUDE.md` § *Paralelización*; acá el **porqué**:

- **El hazard real es el working tree + rama git compartidos**, no los hooks: los validadores
  PostToolUse son stateless por archivo con temporales keyed por PID, sin estado mutable
  compartido. Por eso dos escritores en el **mismo repo** nunca se paralelizan, pero en **repos
  distintos** (working trees separados, cada uno con su rama branch-first asegurada antes de
  spawnear) sí es seguro.
- **@testing es "read-only" solo en tools**: muta DB y contenedor (upgrade, datafixes,
  chrome-install). Se paraleliza con lectores de archivos (@reviewer) porque las superficies son
  disjuntas (DB vs árbol de fuentes), pero es *singleton por DB* — nunca dos corridas sobre la
  misma base.
- **Default `readonly`, no `full`**: el paralelismo de escritores exige juicio (data-independencia
  real entre repos) y el costo de un choque es alto (trabajo pisado); cada dev lo activa cuando lo
  quiere. `off` existe para debug.
- **Fuera de v1 a propósito**: paralelizar módulos independientes del **mismo repo** aislándolos
  en `git worktree` (ya se usa a mano en `.worktrees/`, pero el enjambre no orquesta la creación/
  merge/limpieza de worktrees y ramas por agente). Extensión natural si el nivel `full` demuestra
  valor. El multi-repo de @git-flow sigue secuencial por diseño (skill `git`).

### 3. Agentes (subagentes)

Cada agente es un **subproceso independiente** que se spawnea con la tool `Task`. Tiene su propio contexto y su allowlist de tools (campo `tools` del frontmatter).

**Agentes públicos** (el usuario los ve):
| Agente | Hace | Tools |
|--------|------|-------|
| `client-context` | Escanea la carpeta del cliente, lista módulos, DB | Read, Grep, Glob, Bash |
| `feature-analyst` | Refina una idea cruda (pre-spec, `.docx` con imágenes) **para la planning**: evalúa, cuestiona solo si hace falta, propone alternativas y entrega un refinamiento extendido (decisiones, CA, breakdown, estimación) que el orquestador escribe a un `.md` | Read, Grep, Glob, Bash (read-only) |
| `researcher` | Busca en core/enterprise con grep masivos | Read, Grep, Glob, Bash |
| `code-dev` | Escribe modelos, vistas, wizards, reportes | Read, Edit, Write, Bash, Grep, Glob |
| `scaffold` | Crea estructura base de un módulo nuevo | Read, Edit, Write, Bash, Glob, Grep |
| `reviewer` | Revisa código contra checklist del proyecto | Read, Grep, Glob (read-only) |
| `testing` | py_compile, xmllint, upgrade, datafixes | Read, Grep, Glob, Bash |
| `git-flow` | Operaciones Git genéricas: branch-first + commit/PR/finish a pedido | Read, Bash, Grep, Glob |

**Procedimientos internos** (solo el orquestador los invoca):
| Agente | Hace |
|--------|------|
| `odoo-migration` | Migra módulos entre versiones (origen y destino parametrizables) |
| `module-index-html` | Genera `static/description/index.html` |
| `sdd-generate` | Genera/actualiza la especificación del módulo `specs/<module_technical_name>.md` (una por módulo) |

> Claude Code no oculta subagentes; el `CLAUDE.md` instruye al orquestador a tratar estos tres como procedimientos internos y no exponerlos al usuario.

#### Modelo por agente (model tiering)

Cada agente declara su `model` en el frontmatter según su **rol cognitivo**, no por antojo: así se
paga Opus solo donde hay criterio real y se usa Sonnet para la ejecución determinista. El
orquestador (sesión principal) corre en **Opus**.

| Modelo | Agentes | Por qué |
|--------|---------|---------|
| **opus** | `feature-analyst`, `sdd-generate`, `reviewer`, `odoo-migration` | Juicio de diseño, arquitectura, consistencia y breaking changes — decisiones de **alto costo de error**. |
| **sonnet** | `code-dev`, `scaffold`, `researcher`, `client-context`, `testing`, `module-index-html`, `git-flow` | Ejecución guiada por spec/plantilla/grep/convención, resumen y validación — **determinista**. El criterio fuerte (ej. gate de conflicto SDD, o *cuándo* pushear/abrir PR) lo eleva el agente al orquestador (`Status: BLOCKED`/`NEEDS_INPUT`), no lo resuelve solo. |

> No se usa Haiku (decisión del equipo: calidad sobre ahorro máximo). Si la calidad de algún agente Sonnet
> no alcanza para su tarea, subilo a Opus; el `model` es un parámetro, no un dogma.

### 4. Skills (conocimiento cargable)

A diferencia de los agentes (que son subprocesos), los skills se **inyectan en el contexto** del agente principal con la tool `Skill`. Son más livianos y rápidos.

**Cuándo usar skill vs agente:**
- **Skill**: "Necesito saber cómo se hace un wizard multi-paso" → cargar `odoo-wizards`
- **Agente**: "Implementame el wizard" → spawnear `code-dev`

| Skill | Cuándo cargarlo |
|-------|----------------|
| `odoo-conventions` | Al inicio de cualquier sesión de desarrollo (índice de las 3 fuentes de verdad) |
| `odoo-orm-patterns` | Al diseñar modelos o campos nuevos |
| `odoo-views` | Al crear vistas (list, form, search) |
| `odoo-security` | Al configurar ACLs, grupos, record rules |
| `odoo-qweb-reports` | Al crear reportes PDF |
| `odoo-wizards` | Al crear wizards o TransientModel |
| `odoo-controllers` | Al crear endpoints web/JSON o extender el portal del cliente |
| `odoo-api-integration` | Al consumir/exponer APIs externas (REST/JSON/XML-RPC y afines) |
| `odoo-data-migration` | Al escribir scripts de upgrade o datafixes (migración de datos) |
| `odoo-tests` | Al escribir tests backend o e2e (cuando se piden explícitamente o el repo los requiere vía `.swarm.conf` `TESTS=required` / `E2E=required`; el orquestador lo inyecta a @code-dev en ese caso) |
| `debugging-odoo` | Al diagnosticar errores |
| `git` | Flujo Git: feature/fix desde staging, hotfix desde prod, PRs vía `gh`, release staging→prod a pedido — ramas de deploy Odoo.sh declaradas en `workspace.md` § Deploy (lo carga @git-flow) |
| `plane-tracking` | Seguimiento en Plane.so: ciclo agéntico de tareas (Todo→In Progress→Testing→Done, comentarios, creación directa de issues, plantilla de issue detallado). Lo usa el orquestador (`/plane`, `/tarea`) |
| `sdd-specification` | Al generar especificaciones SDD |
| `minimal-footprint` | Al refinar requerimientos, implementar lógica de negocio o revisar código (anti-over-engineering; lo inyecta el orquestador a @feature-analyst y @code-dev, y lo usa @reviewer) |

> **Linaje de `minimal-footprint`.** La "escalera de decisión" se inspira en el plugin open-source
> *ponytail* (DietrichGebert/ponytail, MIT). Se decidió **no** instalar el plugin (sesgo genérico que
> choca con el boilerplate obligatorio de Odoo/del proyecto, costo de tokens por subagente, dependencia de
> Node, proyecto muy joven) y en su lugar **internalizar la idea** como skill propia, con los
> NO-negociables blindados. Para cosechar mejoras de upstream sin acoplamiento: leer su `SKILL.md` y
> fundir a mano lo que aplique a nuestra skill.

### 5. Hooks — validación automática

**`SessionStart` — auto-actualización del enjambre.** Definido en `.claude/settings.json`, ejecuta
`session_pull.sh` al arrancar/reanudar la sesión (antes de procesar el prompt). Mantiene el repo del
enjambre (`.claude/`) al día con un pull **seguro**: `fetch` read-only siempre, y `pull --ff-only`
**solo** si el árbol está limpio. Nunca bloquea ni pisa trabajo local — si hay cambios sin commitear,
divergencia o no hay red/auth, no toca nada y reporta el estado por `additionalContext` (actualizado /
atrasado N commits / offline / divergencia). Usa `BatchMode` + `timeout` para no colgar el arranque.
No corre en `compact`.

**`SessionStart` — banner de orientación.** Un segundo hook, `session_orient.sh`, imprime al iniciar
una línea de orientación (`systemMessage` visible + `additionalContext` para Claude) con versión de
Odoo, clientes, branch, estado de Docker y # de módulos. Reutiliza `hooks/lib.sh`
(`swarm_orientation_line`). El comando `/contexto` da la versión extendida on-demand.

**Notificaciones de escritorio — diferenciadas.** Tres hooks avisan vía `notify.sh` y el **título
dice qué pasó** (no un genérico), para distinguir etapa vs flujo completo vs input requerido:

| Evento | Hook | Notificación | Cuándo |
|--------|------|--------------|--------|
| `Stop` (fin de turno del orquestador) | `on_stop.sh` | `✅ Turno completo (Ns)` + extracto del resultado; o `⌛ Esperando tu respuesta` + la pregunta, si el turno terminó preguntándote | Completo: solo tareas largas (umbral `NOKEY_NOTIFY_MIN_SECONDS`, default 45s, marcado por `mark_prompt.sh`). Esperando respuesta: **siempre**, sin umbral |
| `SubagentStop` (fin de un subagente — **el flujo sigue**) | `on_subagent_stop.sh` | `🔁 Subagente @<agente> terminó` + `Status`/`Resumen` de su Result Envelope; `⚠️` si vino `BLOCKED`/`NEEDS_INPUT`/`FAILED` | Solo si el turno ya superó el umbral (flujos cortos no pinguean). Apagable con `NOKEY_NOTIFY_SUBAGENTS=0` |
| `Notification` (Claude Code necesita algo) | `on_notification.sh` | `🔐 Permiso requerido` / `⏸ Esperando tu input` según el `type` del evento | Cuando Claude Code lo emite |

`notify.sh` es el transporte **portable**: macOS (`osascript`), WSL→Windows (`powershell.exe`,
toast/balloon), Linux nativo (`notify-send`) y fallback a bell. Best-effort, nunca bloquea.

El hook **`PostToolUse`** definido en `.claude/settings.json` (matcher `Write|Edit`) ejecuta `post_write.sh` cada vez que se escribe o edita un archivo. El dispatcher lee el JSON del evento por stdin, extrae el `file_path` y, si es `.py` o `.xml`, ejecuta dos scripts en secuencia:

```
Claude escribe/edita un archivo
  → Claude Code dispara el hook PostToolUse
    → post_write.sh recibe el JSON por stdin
      → Filtra: solo .py/.xml
        → Ejecuta validate_files.sh          (warnings, no bloquea)
        → Ejecuta check_breaking_changes.sh  (errores de la versión → bloquea con exit 2)
```

**Hook 1 — `validate_files.sh`**: valida convenciones del proyecto
- Headers `# -*- coding: utf-8 -*-` y `<?xml version="1.0"?>`
- Vim modelines al final
- Sintaxis Python (`py_compile`) y XML (`xmllint --noout`)
- Manifiesto: chequeo suave de que declare `license` (default del proyecto: LGPL-3)
- **Doc-check**: detección estructural — si el archivo pertenece a un módulo custom (tiene `__manifest__.py` ancestro y no está bajo core/enterprise) y el módulo no tiene `README.md` ni `index.html` → warning. No depende del nombre de la carpeta de addons (ver `hooks/lib.sh`)

**Hook 2 — `check_breaking_changes.sh`** (data-driven): lee `ODOO_VERSION` de `workspace.md` y
carga los patrones prohibidos desde `references/patterns/v{ODOO_VERSION}.patterns`. Si el archivo
escrito contiene un patrón prohibido de esa versión, **bloquea** (`exit 2`) y devuelve el detalle a
Claude. Si no hay archivo de patrones para esa versión, no bloquea. Para v19, por ejemplo, detecta
`<tree>`, `<group expand=>`, `company_type`, `_sql_constraints`, `groups_id`, `user_has_groups`,
`category_id` en `res.groups`. **Soportar otra versión = soltar otro `.patterns`, sin tocar el script.**

Además de los dos validadores, `post_write.sh` inyecta recordatorios **al agente** vía
`additionalContext` (no bloqueantes): documentación del módulo faltante/desactualizable, spec SDD
(drift de versión / update en sitio), índice README del repo, y **política de tests por repo**
(`.swarm.conf`, dos ejes independientes): si el repo declara `TESTS=required` y el módulo no tiene
`tests/` con `test_*.py`, recuerda agregar tests backend de los flujos troncales; si declara
`E2E=required` y el módulo tiene superficie de UI (controllers/JS) sin tour, recuerda —por juicio,
solo si el cambio toca un flujo de UI troncal— agregar un Tour de Odoo (e2e). Todo se corre antes de
cerrar (para e2e, un tour SKIPPED por falta de Chrome no cuenta como pasado).

### 6. SDD — Specification-Driven Development

Para features complejas, el flujo es:

```
Usuario: "Quiero feature X en módulo Y"
  → Orquestador: ¿es compleja? (3+ modelos/métodos)
    → Sí → "¿Generamos una spec primero?" (recomendado)
      → Usuario acepta
        → Cargar skill sdd-specification
        → sdd-generate: investiga + genera/edita specs/<module_technical_name>.md
        → Usuario revisa y aprueba → spec state = approved
        → code-dev: implementa siguiendo la spec + edita la spec en sitio + sincroniza versión
        → reviewer: compara spec vs implementación + valida sync de versión
        → Spec state = verified
```

**Una spec por módulo, documento vivo.** La spec vive en `<módulo>/specs/<module_technical_name>.md`
(**un solo archivo por módulo**) y describe el módulo *como está hoy*: objetivo, alcance, modelos,
campos, métodos, vistas, seguridad, reglas de negocio, edge cases, criterios de aceptación. Tres
reglas la rigen:

1. **Fuente de verdad al levantar contexto**: si un módulo tiene `specs/`, la spec se lee antes que
   el README/código (`client-context`, `code-dev`, `sdd-generate`).
2. **Versión sincronizada**: la `Version` de la spec espeja el `version` del `__manifest__.py`
   (formato `x.x.x`, sin prefijo de serie de Odoo). Cada cambio bumpea ambos juntos; el hook
   `post_write.sh` avisa si hay drift.
3. **Gate de conflicto + update en sitio**: si un cambio contradice la spec, el enjambre **frena y
   consulta al usuario** antes de tocar código; al implementar, la spec se **edita en sitio** (no
   acumulativa — el historial lo da git).

### 7. Scripts — la capa determinista (ahorro de tokens)

Lo que es **mecánico y repetible no se razona con el LLM**: vive como script en `.claude/scripts/`
y los agentes lo **invocan** en vez de reconstruirlo en cada corrida. Todos reusan los helpers de
`hooks/lib.sh` (parsing de `workspace.md`, detección de módulos/specs/versiones/ramas) y son
read-only salvo donde se indica. `/salud` verifica que estén presentes y ejecutables.

| Script | Qué resuelve | Quién lo invoca |
|--------|--------------|-----------------|
| `odoo_runtime.sh` | Runtime Odoo resuelto una vez (engine/contenedor/DB): logs, upgrade/install/test, psql, backup/restore (muta DB, `restore` pide `--yes`), validate, deps | @testing, skill `debugging-odoo` |
| `cliente.sh` | Inventario del repo de un cliente: módulos, versiones, SDD + estado + **drift**, docs, integraciones | @client-context (paso 1) |
| `git_state.sh` | Estado Git parseable (toplevel, tipo de repo, rama y si es protegida, staged, módulos) | @git-flow |
| `extract_docx.sh` | Ingesta `.docx`: texto + imágenes embebidas con cadena de fallback fija | @feature-analyst |
| `spec_lint.py` | Linter de specs SDD: metadatos, estado, version sync, cobertura CA↔T, dependencias, anclajes `path:L#` | @sdd-generate (auto-chequeo); orquestador (pre-pass de analyze) |
| `review_static.sh` | Pre-pass estático de review sobre el módulo completo (convenciones + breaking changes + señales sudo/SQL/ACL/XML IDs + spec_lint si es SDD) | **Orquestador**, que inyecta la salida a @reviewer (sin Bash a propósito) |

La división del trabajo es deliberada: el script **detecta** (barato, determinista, sin variar entre
corridas); el agente **juzga** (severidad, falsos positivos, semántica). Los hooks siguen siendo el
gate al escribir; estos scripts son la versión **on-demand por módulo** para orientar/revisar.

---

## 🔄 Flujo típico: "Implementar feature X en módulo Y"

```
1. ORQUESTADOR lee workspace.md (versión, paths, cliente) y recibe el request
   │
   ├── ¿Es módulo de un cliente? → client-context
   │
   ├── ¿Feature compleja? → ofrece SDD → sdd-generate
   │
   ├── BRANCH-FIRST: ¿el repo está en una rama larga (main / stagesunra)? → git-flow crea la rama
   │   de trabajo: feature/fix desde staging; hotfix desde prod (workspace.md § Deploy, skill git)
   │
   ├── ¿Módulo nuevo? → scaffold
   │
   ├── code-dev implementa (sobre la rama de feature/fix)
   │   │
   │   └── Cada archivo escrito → HOOKS validan automáticamente
   │
   ├── ¿Falta documentación? → module-index-html
   │
   ├── testing (opcional)
   │
   ├── reviewer (si se usó spec)
   │
   └── ORQUESTADOR reporta al usuario
       └── Handoff Git: cambios en la rama de feature/fix; commit/push/PR vía git-flow SOLO a pedido
```

---

## 📐 Convenciones clave

**Fuente única: `AGENTS.md`** — no se resumen acá para no driftear. Ahí están idioma (código en
inglés, comentarios en español, UI con `_()`), encabezados/modelines obligatorios, plantillas de
`__manifest__.py`/modelo/vista, estructura de módulo, naming, convenciones XML, ORM y reglas de
edición. Reglas de oro a tener presentes: **nunca** tocar `odoo/`/`enterprise/` (heredar con
`_inherit`), **nunca** trabajar un módulo sin documentación, y no escribir tests salvo que se pidan
o que el repo los requiera (**política por repo**: `.swarm.conf` con dos ejes independientes —
`TESTS=required` backend → todo módulo tocado cierra con tests de sus flujos troncales; `E2E=required`
e2e de UI → los módulos con flujo de UI troncal llevan un Tour de Odoo; todo ejecutado).

---

## ⚠️ Breaking changes

**No se listan aquí** (evita drift). Viven en `.claude/references/`, por versión:
- `references/{ODOO_VERSION-1}_to_{ODOO_VERSION}.md` — salto de migración
- `references/v{ODOO_VERSION}_gotchas.md` — gotchas curados
- `references/common_patterns.md` — patrones comunes

El hook valida automáticamente los detectables por patrón (`references/patterns/v{ODOO_VERSION}.patterns`).

---

## 🛠️ Comandos rápidos

| Comando | Hace |
|---------|------|
| `/odoo-module <nombre>` | Crear nuevo módulo |
| `/odoo-model <nombre>` | Crear nuevo modelo |
| `/odoo-view <nombre>` | Crear vistas para un modelo |
| `/odoo-inherit <modelo>` | Extender modelo existente |
| `/analizar-core <módulo>` | Analizar módulo del core |
| `/analizar-enterprise <módulo>` | Analizar módulo enterprise |
| `/refinar-feature <requerimiento>` | Refinar una idea cruda (pre-spec) para la planning (`.md`) |
| `/contexto` | Resumen de orientación: versión Odoo, cliente/DB, Docker, git, módulo actual y specs |
| `/salud` | Chequeo de salud del entorno (workspace.md, versión, paths, references, Docker, deploy, Plane, git) |
| `/plane [subcomando]` | Operar el seguimiento en Plane.so (list/next/get/create/update/move/comment) |
| `/tarea [#seq]` | Tomar una tarea de Plane (la próxima o una dada) y resolverla de punta a punta |

---

## 📊 Resumen

| Capa | Cantidad | Rol |
|------|----------|-----|
| Entorno | `.claude/workspace.md` | Versión, paths, Docker, DB, cliente (por dev) |
| Orquestador + convenciones | `CLAUDE.md` + `AGENTS.md` | Coordinación central y reglas globales |
| Configuración | `.claude/settings.json` | Permisos + hook de validación |
| Agentes públicos | 8 | Trabajo especializado (incluye @git-flow) |
| Procedimientos internos | 3 | Subrutinas del orquestador |
| Skills | 15 | Conocimiento cargable |
| Commands | 11 | Atajos de tareas comunes (incluye `/contexto`, `/salud`, `/plane`, `/tarea`) |
| Hooks | varios | Validación, protección de core, auto-update + orientación y notificaciones |
| References | por versión | Breaking changes (docs + patterns del hook) |
| Assets | template HTML + plantillas de test/política de repo | Documentación de módulos y `.swarm.conf` |

---

*Enjambre Nokey — Claude Code (agnóstico de versión de Odoo)*
