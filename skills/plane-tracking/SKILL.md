---
name: plane-tracking
description: Seguimiento del proyecto en Plane.so. Cómo el enjambre lista/crea/actualiza/mueve issues vía .claude/scripts/plane.sh, el modelo de estados (incl. Testing), la disciplina agéntica de sync (In Progress al arrancar, Testing al quedar en validación, Done al verificar, comentarios de avance, creación directa de issues) y la plantilla de issue bien detallado. Config per-dev en workspace.md + API key en el archivo de secretos. Cargar cuando la tarea implique reflejar avance en Plane o tomar tareas (/tarea).
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

Estados reales del proyecto (grupos entre paréntesis; verificables con `plane.sh states`):

| Estado | Grupo | Cuándo |
|--------|-------|--------|
| **Backlog** | backlog | Idea/pendiente sin arrancar ni planificar. |
| **Todo** | unstarted | Planificada y **bien detallada**, lista para tomar (pool de `next`/`/tarea`). |
| **In Progress** | started | En desarrollo **ahora**. |
| **Testing** | started | Implementada, **en validación**: pusheada a la rama de integración y esperando prueba funcional del usuario (o, en repos Odoo.sh, desplegada en `STAGING_URL` — ver `workspace.md` § Deploy). |
| **Done** | completed | Terminada y **verificada**. |
| **Cancelled** | cancelled | Descartada / no se hace. |

Los estados se referencian **por nombre** (`plane.sh` resuelve el nombre → id). Prioridades válidas:
`urgent`, `high`, `medium`, `low`, `none`.

## CLI — `plane.sh <subcomando>`

```
env                                   config resuelta + test de conexión
states | labels | members             catálogos del proyecto
list [--state N] [--priority P] [--search TXT] [--assignee M] [--limit N]
next [--state N] [--assignee M]       la PRÓXIMA tarea a tomar (más urgente de Todo; detalle completo)
get <#seq|uuid>                       detalle (acepta el #número o el UUID)
create --name "..." [--desc "..."] [--state N] [--priority P] [--label L]... [--assignee M]...
update <#seq|uuid> [--name] [--desc] [--state] [--priority] [--label] [--assignee M]...
move <#seq|uuid> "<Estado>"           atajo para cambiar el estado
comment <#seq|uuid> "texto"           agrega un comentario (acepta HTML)
delete <#seq|uuid> --yes              DESTRUCTIVO (exige --yes y OK explícito del usuario)
```

- Las tareas se refieren por su **#número** (`sequence_id`, ej. `9`) o por su UUID.
- `--desc`/`comment` aceptan texto plano (se envuelve en `<p>` escapado) o HTML directo.
- `--assignee` acepta UUID o (substring único de) display name (`plane.sh members`).
- `next` ordena por prioridad (urgent→none) y, a igual prioridad, el issue más viejo.
- Ejemplos:
  ```bash
  bash .claude/scripts/plane.sh next
  bash .claude/scripts/plane.sh move 9 "In Progress"
  bash .claude/scripts/plane.sh comment 9 "Implementado y pusheado a <code>develop_19.0</code> (commit abc1234); listo para validar."
  bash .claude/scripts/plane.sh create --name "Fix numeración diario" --state Todo --priority high \
       --desc "Resecuenciar asientos mal numerados."
  ```

## Ciclo de vida agéntico (qué hace el orquestador)

Mantené Plane como **espejo fiel y en tiempo real** del trabajo. El enjambre gestiona las tareas
solo (política confirmada jul-2026): mueve estados, comenta, crea y edita issues **sin pedir
permiso antes — informa después** en su reporte. La única operación que sigue exigiendo OK previo
es `delete`.

1. **Tomar una tarea** (pedido "trabajá la #N" / "agarrá la próxima" → comando `/tarea`):
   `get <#seq>` (o `next`) → mover a **In Progress** → resolver con el flujo que corresponda
   (Implementa/Modifica/Refina/Migra de `CLAUDE.md`), directo sobre la rama de integración del repo
   (típ. `develop_19.0`; modelo directo, sin git flow — skill `git`).
2. **Durante el trabajo**, comentá los hitos que le sirvan a un humano que mira el tablero: decisión
   de diseño relevante, bloqueo encontrado. Sin ruido: hitos, no cada paso.
3. **Al terminar la implementación** (código listo, validado localmente y pusheado a la rama de
   integración a pedido) → **Testing** + `comment` con: rama/commit, módulos y versiones tocados,
   qué validar y **dónde**. Si el issue queda esperando validación humana, Testing es su estado
   estable — no lo cierres vos.
4. **Al verificar** (el usuario confirma, o la validación fue automatizable y pasó) → **Done** +
   `comment` de cierre (resultado final).
5. **Si la tarea no se puede completar** (falta contexto, decisión, dependencia externa): NO
   abandones en silencio — `comment` con el bloqueo concreto, dejala en In Progress (o devolvela a
   Todo si no se empezó nada) y reportá `NEEDS_INPUT`/`BLOCKED` al usuario.
6. **Trabajo nuevo no trackeado**: si surge trabajo sin issue (pedido directo del usuario, hallazgo
   colateral, breakdown de un refinamiento), **crealo directo** con nombre + descripción detallada
   (plantilla de abajo) y avisale al usuario en el reporte ("creé #NN"). No dupliques: `list
   --search` antes de crear. Los hallazgos colaterales nacen en **Backlog** (que los priorice el
   humano); lo que el usuario pidió trabajar ya, en **Todo**/**In Progress**.
7. **Cambio de alcance** sobre una tarea existente → `update` (título/desc, en sitio), no un issue
   nuevo. Enriquecer una descripción pobre con lo aprendido al trabajarla también es `update` — una
   tarea bien detallada es la materia prima de `/tarea`.

## Plantilla de issue bien detallado

Las tareas en Todo deben poder tomarse **sin contexto verbal extra**. Al crear (o enriquecer) un
issue, la descripción incluye (HTML simple: `<p>`, `<ul>`, `<code>`):

- **Objetivo** (1-2 frases: qué se quiere y por qué / valor de negocio).
- **Módulo(s)/área**: módulo técnico afectado (o "nuevo módulo"), modelos/flujos que toca.
- **Criterios de aceptación**: lista verificable (qué tiene que pasar para darla por buena).
- **Restricciones/decisiones ya tomadas** (si las hay; ej. "reusar Field Service, no modelo nuevo").
- **Cómo validar**: pasos de prueba y en qué entorno (local; o, en repos Odoo.sh, `STAGING_URL`).

Si al tomar una tarea la descripción no alcanza para arrancar (sin CA, ambigua), primero completala:
preguntá lo mínimo al usuario, `update` con lo aclarado, y recién después implementá.

## Reglas (outward-facing)

- Crear/editar/mover/comentar escribe en el Plane del cliente: hacelo con criterio profesional —
  prosa clara, sin jerga interna del enjambre, sin volcar logs crudos. **Informá siempre después**
  en tu reporte qué issues tocaste (`#seq` y qué cambió).
- **Nunca** `delete` sin OK explícito del usuario (además el script exige `--yes`).
- **Nunca** inventes estados/labels/prioridades: si el nombre no existe, el script lista los válidos.
- No re-priorices tareas existentes por tu cuenta (la prioridad es del humano); sí podés setear
  prioridad al **crear** un issue si el contexto la hace obvia.
- La API key **no se loguea ni se comita**; vive solo en el archivo de secretos.
