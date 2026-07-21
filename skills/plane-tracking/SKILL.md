---
name: plane-tracking
description: Seguimiento del proyecto en Plane.so. Cómo el enjambre lista/crea/actualiza/mueve issues vía .claude/scripts/plane.sh, el modelo de estados, y la disciplina de sync (mover a In Progress al arrancar, a Done al cerrar). Config per-dev en workspace.md + API key en el archivo de secretos. Cargar cuando la tarea implique reflejar avance en Plane.
---

# Seguimiento del proyecto — Plane.so

> **Fuente única de la operatoria Plane del enjambre.** El proyecto se trackea en **Plane.so**; el
> enjambre lo mantiene en sync a través de un único wrapper: `.claude/scripts/plane.sh`. Ningún agente
> arma llamadas HTTP a Plane a mano ni hardcodea la API key o el project id.

## Config (per-dev, sin secretos en el repo)

Todo se resuelve solo desde `workspace.md` + el archivo de secretos (vía `hooks/lib.sh`):

- **No-secreto** (markers en `workspace.md`, iguales para todo el equipo):
  `PLANE_WORKSPACE`, `PLANE_PROJECT`, `PLANE_API_BASE` (opcional; default `https://api.plane.so/api/v1`).
- **Secreto per-dev**: `PLANE_API_KEY` en el archivo declarado por `NOKEY_SECRETS_FILE`
  (formato `KEY=value`, `chmod 600`, **fuera** del repo). Se saca en Plane → avatar →
  *Settings → API tokens → Add API token*.

Verificá la config con `plane.sh env` (muestra todo y prueba la conexión; enmascara la key). Si algo
falta, el script sale con un error que dice exactamente qué declarar y dónde.

## Modelo de estados

El proyecto usa los estados estándar de Plane (grupos entre paréntesis):

| Estado | Grupo | Cuándo |
|--------|-------|--------|
| **Backlog** | backlog | Idea/pendiente sin arrancar ni planificar. |
| **Todo** | unstarted | Planificada, lista para tomar. |
| **In Progress** | started | En desarrollo **ahora**. |
| **Done** | completed | Terminada y verificada. |
| **Cancelled** | cancelled | Descartada / no se hace. |

Los estados se referencian **por nombre** (`plane.sh` resuelve el nombre → id). Prioridades válidas:
`urgent`, `high`, `medium`, `low`, `none`.

## CLI — `plane.sh <subcomando>`

```
env                                   config resuelta + test de conexión
states | labels | members             catálogos del proyecto
list [--state N] [--priority P] [--search TXT]
get <#seq|uuid>                       detalle (acepta el #número o el UUID)
create --name "..." [--desc "..."] [--state N] [--priority P] [--label L]... [--assignee UUID]...
update <#seq|uuid> [--name] [--desc] [--state] [--priority] [--label]
move <#seq|uuid> "<Estado>"           atajo para cambiar el estado
comment <#seq|uuid> "texto"           agrega un comentario (acepta HTML)
delete <#seq|uuid> --yes              DESTRUCTIVO (exige --yes)
```

- Las tareas se refieren por su **#número** (`sequence_id`, ej. `9`) o por su UUID.
- `--desc`/`comment` aceptan texto plano (se envuelve en `<p>` escapado) o HTML directo.
- Ejemplos:
  ```bash
  bash .claude/scripts/plane.sh list --state Backlog
  bash .claude/scripts/plane.sh move 9 "In Progress"
  bash .claude/scripts/plane.sh comment 9 "Implementado en feature/task_9; PR #NN."
  bash .claude/scripts/plane.sh create --name "Fix numeración diario" --state Todo --priority high \
       --desc "Resecuenciar asientos mal numerados."
  ```

## Disciplina de sync (qué hace el orquestador)

Mantené Plane como espejo fiel del trabajo real, **sin sobre-actuar**:

1. **Al arrancar** una tarea que corresponde a un issue existente → `move <#seq> "In Progress"`.
2. **Al cerrarla** (verificada) → `move <#seq> "Done"`, y si aporta, un `comment` con el resultado
   (rama de feature, PR, módulo/versión). El commit/PR sigue siendo **a pedido** (ver skill `git`);
   el comment en Plane solo **describe** dónde quedó.
3. **Trabajo nuevo no trackeado**: si el usuario pide algo que no tiene issue, **ofrecé** crearlo; no
   lo crees en silencio ni inventes tareas que nadie pidió.
4. **Un cambio de alcance** sobre una tarea existente → `update` (título/desc), no un issue nuevo.

## Reglas (outward-facing)

- Crear/editar/mover/borrar issues **escribe en el Plane del cliente** → es outward-facing.
  **Proponé antes de crear en lote** y confirmá con el usuario; para un único `move`/`comment` de
  sync rutinario no hace falta pedir permiso.
- **Nunca** `delete` sin OK explícito del usuario (además el script exige `--yes`).
- **Nunca** inventes estados/labels/prioridades: si el nombre no existe, el script lista los válidos.
- La API key **no se loguea ni se comita**; vive solo en el archivo de secretos.
