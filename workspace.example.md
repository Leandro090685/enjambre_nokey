# workspace.md — Cómo está armado MI workspace

> Copiá este archivo a `.claude/workspace.md` y describí tu entorno **con tus palabras**.
> `workspace.md` está en `.gitignore`: es por desarrollador, no se commitea.
>
> Los agentes leen este archivo para entender dónde está cada cosa y cómo correr Odoo. No hace
> falta seguir un formato rígido: contá lo que un compañero necesitaría saber para ubicarse. Lo
> único que conviene dejar explícito y parseable es la **versión de Odoo** (el hook la usa).
>
> Esto es un ejemplo — borralo y escribí el tuyo.

---

## Versión de Odoo

```
ODOO_VERSION: 19
```

Dejá esta línea tal cual (con el número que corresponda). A partir de la versión, el agente
deduce solo qué breaking changes y referencias aplican (`.claude/references/`) — no hace falta
que las listes.

---

## Paralelización de subagentes (opcional)

```
PARALLELISM: readonly
```

Cuánto paraleliza el orquestador (política completa en `CLAUDE.md` § *Paralelización*; rationale
en `ENJAMBRE.md` § *Paralelización por niveles*). Valores:
- `off` — todo secuencial (debug).
- `readonly` — **default si no declarás nada**: solo subagentes read-only e independientes en
  paralelo (@researcher + @client-context, etc.).
- `full` — además pares de fase segura (@reviewer + @testing tras @code-dev; docs + tests) y
  escritores en paralelo **solo entre repos distintos**. Nunca dos escritores en el mismo repo ni
  dos @testing en la misma DB.

---

## Dónde está el workspace (paths con nombre)

En prosa: mi workspace root es `~/repos/19`, con el core en `odoo/`, enterprise en `enterprise/` y
los addons custom en `extra-addons/`. (Ajustá a tu layout; si es distinto, explicalo igual.)

Además, declaro **paths con nombre** (marcadores parseables, igual que `ODOO_VERSION`) para que
agentes y hooks resuelvan ubicaciones sin adivinar. Cada repo se nombra **una sola vez** con un
*handle* `NOMBRE: path` (relativo al root, o absoluto si empieza con `/` o `~`); después las
**listas** agrupan esos handles. Así no se duplica ningún path.

```
WORKSPACE_ROOT: ~/repos/19            # opcional: solo si .claude no está dentro del root

# Core / enterprise (handle -> path). Se EXCLUYEN de la validación (nunca se tocan).
ODOO_CORE:       odoo
ODOO_ENTERPRISE: enterprise

# Addons de terceros / OCA reusados en más de un proyecto (un handle por repo, opcional)
ODOO_ADDONS_THIRD_PARTY: extra-addons/odoo_addons_third_party

# Customizaciones propias (un handle por repo/proyecto)
ODOO_CUSTOM_SUNRA: extra-addons/odoo_customization_sunra

# Agrupaciones (listas de handles, o paths directos). Es lo que consumen agentes/hooks:
CORE_ROOTS:     ODOO_CORE ODOO_ENTERPRISE
PRODUCT_ADDONS: ODOO_ADDONS_THIRD_PARTY
CLIENT_ADDONS:  ODOO_CUSTOM_SUNRA
```

**Todo esto es OPCIONAL.** Si no declarás nada, el enjambre igual funciona: detecta los módulos
custom por estructura (su `__manifest__.py`, excluyendo core/enterprise) y usa defaults
(`odoo`/`enterprise` como core, `extra-addons/` como raíz de addons). Los marcadores te sirven si
tu layout no es el estándar (p. ej. core en `19.0/addons/`) o para que los agentes distingan
**addons propios** (`CLIENT_ADDONS`) de **addons de terceros** (`PRODUCT_ADDONS`).

---

## Cómo corro Odoo: Docker, Podman o venv

Marcá lo que uses y agregá lo mínimo para que el agente sepa cómo ejecutar/validar:

- [x] **Docker** — Odoo corre en un contenedor. (El agente puede descubrir el nombre con
  `docker ps` y preguntarte la base de datos cuando haga falta; no hace falta hardcodearlos acá.)
- [ ] **Podman** — Odoo corre en un contenedor. (Igual que Docker pero con `podman ps`.)
- [ ] **venv / local** — Odoo corre con un virtualenv local. Indicá dónde está el venv y el
  comando para levantarlo si no es el estándar.

**Marcadores opcionales del contenedor.** Si declarás el contenedor, los comandos `/contexto` y
`/salud` (y el banner de orientación al iniciar sesión) chequean si está corriendo. Si no los
declarás, degradan con una nota — no es obligatorio. La tooling **no infiere el engine**: declaralo
explícito con `ODOO_CONTAINER_ENGINE` (`docker` o `podman`; default `docker` si se omite). En venv
no declarás `ODOO_CONTAINER` y el chequeo queda `n-a`:

```
ODOO_CONTAINER:        nokey-odoo-1    # nombre del contenedor de Odoo
ODOO_CONTAINER_ENGINE: docker          # docker | podman (default docker)
ODOO_DB_CONTAINER:     nokey-db-1      # nombre del contenedor de la base de datos (informativo)
```

Cualquier detalle extra del entorno que sea no obvio (rutas dentro del contenedor, un script
propio para levantar Odoo, etc.) va acá en prosa.

---

## Deploy: repos Odoo.sh (opcional)

**El modelo Git del enjambre es directo** (ver skill `git`): se commitea y pushea directo sobre la
rama de integración del repo, sin ramas de feature/fix ni PR. Estos markers **no** cambian ese
modelo — solo declaran la **excepción Odoo.sh**: que ciertas ramas largas del repo están atadas a un
entorno desplegado, de modo que un `git push` a esa rama **despliega el entorno**. Los leen el skill
`git`, el agente `@git-flow`, `git_state.sh` (marca la rama como de deploy) y `/salud`:

```
DEPLOY_PLATFORM: odoo.sh                        # odoo.sh | otro (informativo)
PROD_BRANCH:     main                           # rama larga de producción
PROD_URL:        https://micliente.odoo.com     # URL del entorno de producción
STAGING_BRANCH:  staging                        # rama larga de staging
STAGING_URL:     https://stage-micliente.odoo.com
```

Con esto declarado, el push a `STAGING_BRANCH`/`PROD_BRANCH` **se confirma con el usuario antes**
(deploya el entorno) — pero se sigue commiteando directo, sin PR ni ramas de feature. Sin estos
markers (el caso normal de los repos actuales), ninguna rama deploya: push directo, sin ceremonia.
⚠️ Recordá: si la plataforma es Odoo.sh, **push a rama de deploy = deploy real** del entorno.

---

## Seguimiento del proyecto: Plane.so (opcional)

Si el proyecto se trackea en **Plane.so**, el enjambre lo opera con `.claude/scripts/plane.sh`
(skill `plane-tracking`, comando `/plane`). Declará la config **no-secreta** del proyecto (misma para
todo el equipo):

```
PLANE_WORKSPACE: nokey
PLANE_PROJECT:   ea36bfb4-9470-4960-a2fd-2e3be17403bb
PLANE_API_BASE:  https://api.plane.so/api/v1
```

La **API key es per-dev** y va en el archivo de secretos (abajo) como `PLANE_API_KEY=...`, **nunca**
acá. Se obtiene en Plane → avatar → *Settings → API tokens*. Sin estos markers, el seguimiento en
Plane queda desactivado y el resto del enjambre funciona igual.

---

## Secretos per-dev (archivo local, FUERA del repo)

> 🔒 **Política**: los secretos per-dev (tokens/passwords) **NUNCA** van dentro del repo del enjambre.
> Viven en un archivo local en tu HOME y se declaran con el
> marcador `NOKEY_SECRETS_FILE` en `workspace.md`.

1. Creá el archivo (path común para todo el equipo) y dale permisos restrictivos:
   ```bash
   touch ~/.claude/nokey-enjambre-secrets.env && chmod 600 ~/.claude/nokey-enjambre-secrets.env
   ```
2. Declaralo en tu `workspace.md` (default si lo omitís: ese mismo path):
   ```
   NOKEY_SECRETS_FILE: ~/.claude/nokey-enjambre-secrets.env
   ```
3. Poné adentro las credenciales que tus propias integraciones necesiten, formato `KEY=value` (una
   por línea). El enjambre no trae integraciones propietarias por defecto — Git es genérico (ramas de
   feature/fix, commits, PR vía `gh`/GitHub; ver skill `git`). Si conectás algo propio (una API
   externa, un webhook, etc.), documentá acá qué claves necesita. Ejemplo real de este proyecto:
   `PLANE_API_KEY=plane_api_xxx` para el seguimiento en Plane (skill `plane-tracking`).

> Los scripts cargan estas vars desde el archivo (parser, no `source`) **solo si no están ya en el
> entorno** — así que si preferís, podés setearlas como `env` en tu `~/.claude/settings.json` global y
> tienen prioridad. Lo que **no** se hace es ponerlas en el repo (`workspace.md`/`settings.local.json`).
> Si versionás `~/.claude` como dotfiles, **gitignorá** el archivo de secretos.
<!-- vim:expandtab:smartindent:tabstop=4:softtabstop=4:shiftwidth=4-->
