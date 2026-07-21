---
name: debugging-odoo
description: Tecnicas de debugging para Odoo segun el entorno declarado en workspace.md (Docker, Podman o venv local). Logs, py_compile, xmllint, shell interactivo, profiling, upgrades, backups y solucion de problemas comunes.
---

# Debugging — Odoo

> **Runtime resuelto por script — NO armes comandos docker/psql a mano.**
> El wrapper `.claude/scripts/odoo_runtime.sh` resuelve el entorno (engine docker/podman,
> contenedor, DB, venv) **una sola vez** desde `workspace.md` y expone subcomandos fijos.
> Usalo SIEMPRE que exista; recién si falla o falta, resolvé los placeholders a mano con el
> apéndice del final.

## El wrapper: `odoo_runtime.sh`

```bash
S=.claude/scripts/odoo_runtime.sh   # (path relativo al workspace root)

$S env                              # entorno resuelto (modo, engine, contenedor, estado, db)
$S ps                               # contenedores corriendo
$S logs [--follow] [--tail N] [--grep PATRON]
$S errors [--tail N]                # logs filtrados por error|critical|traceback
$S shell <db>                       # imprime el comando interactivo listo para pegar (requiere TTY)
$S upgrade <db> <mod1[,mod2..]>     # odoo -u --stop-after-init
$S install <db> <mod1[,mod2..]>     # odoo -i --stop-after-init
$S test <db> <mods> [--test-tags TAGS]   # upgrade con --test-enable (o tags puntuales)
$S run-tests <db> <TAGS>            # solo --test-tags (ej: /mi_modulo:TestClase.test_metodo)
$S psql <db> [-c SQL]               # psql contra la DB (sin -c lee SQL de stdin)
$S backup <db> [out.sql.gz]         # pg_dump | gzip; imprime BACKUP_FILE=...
$S restore <db> <file> --yes        # DESTRUCTIVO: pide --yes explicito
$S validate <modulo_path>           # py_compile + XML well-formed + IDs duplicados
$S dup-ids <modulo_path>            # solo IDs XML duplicados
$S deps <module_name>               # modulos custom que dependen de el (regresion)
```

Notas:
- `<db>` es la base de trabajo — si no es obvia, **preguntá** (puede haber varias); no la inventes.
- `validate` corre lo mismo que el hook `validate_files.sh` pero **on-demand sobre el módulo
  completo** (el hook valida archivo por archivo al escribir).
- Los duplicados de `dup-ids` pueden ser herencia legítima de vista (mismo XML ID adrede): revisar.
- Para flags de odoo no cubiertos (ej. `--log-level=debug`, `--profile`), pedile el prefijo a
  `$S shell <db>` / `$S env` y armá el comando sobre esa base:
  `docker exec <container> odoo -d <db> -u <mod> --stop-after-init --log-level=debug`.

## Logging en código

```python
import logging
_logger = logging.getLogger(__name__)

_logger.info("Procesando %s registros", len(records))
_logger.warning("Campo %s vacio para el registro %s", field_name, rec.id)
_logger.error("Error al procesar: %s", str(e))
```

## Odoo Shell interactivo

`$S shell <db>` imprime el comando (ej. `docker exec -it <container> odoo shell -d <db>`). Adentro:

```python
>>> partners = env["res.partner"].search([("is_company", "=", True)], limit=5)
>>> partners.mapped("name")
>>> move = env["account.move"].browse(1); move.action_post()
>>> env["account.move"].fields_get()          # campos de un modelo
>>> env.user.company_id.name                  # contexto multi-compania
>>> env.cr.commit()   # SOLO en shell interactivo el commit es manual
>>> exit()
```

## Tests automatizados (si el módulo trae tests, se piden, o el repo los requiere)

> Convención del proyecto: **no se escriben tests salvo que se pidan o que el repo los requiera**
> (`.swarm.conf` con `TESTS=required` backend y/o `E2E=required` e2e — alcance en skill
> `odoo-tests`). Cuando existan:
> `$S test <db> <modulo>` (todos) o `$S run-tests <db> '<TAGS>'` con tags
> `/<module>:TestClass`, `/<module>:TestClass.test_method`, `post_install,/<module>`.
> Tags: `standard` (default), `at_install`, `post_install`; excluir con prefijo `-`.
> Estructura de la clase (base `TransactionCase`/`SingleTransactionCase`/`HttpCase`,
> `@tagged(...)`, datos en `setUpClass`): ver AGENTS.md → "Tests".

### Tours e2e (UI) — requieren Chrome en el contenedor

Los tours (`HttpCase.start_tour`) manejan un **Chrome headless** real. Odoo lo busca en el PATH
(`chromium`, `chromium-browser`, `google-chrome`, `google-chrome-stable`) o respeta `ODOO_BROWSER_BIN`.

- **Verificar Chrome**: `$S chrome-check` → imprime `CHROME=<path>` o `CHROME=missing`.
- **Correr solo el e2e**: `$S run-tests <db> '/<modulo>,<tag_e2e>'` (el tag lo define el `@tagged`
  del test — ver `odoo-tests`).
- ⚠️ **SKIPPED ≠ PASSED**: sin Chrome, Odoo emite `unittest.SkipTest("Failed to detect chrome
  devtools port…")` y el tour **se saltea, no falla**. Un run "0 passed / N skipped" **no** valida
  nada — no lo reportes como verde. En el log buscá `skipped` / `SkipTest`, no solo `FAIL`.
- **Instalar Chrome** (si `chrome-check` da `missing`): **primero avisá y preguntá al usuario** —
  muta el contenedor. Con su OK: `$S chrome-install` (hace `apt-get install -y chromium` como root
  dentro del contenedor y re-verifica). Alternativa: montar un `google-chrome` y exportar
  `ODOO_BROWSER_BIN`. ⚠️ El `apt-get` dentro del contenedor **persiste al restart pero se pierde si
  se recrea** el contenedor/imagen — para permanencia, agregar `chromium` al Dockerfile de la imagen
  dev (cambio de entorno, fuera del repo del enjambre).

## Errores comunes y soluciones

### `KeyError: 'field_name'`
- El campo no existe en el modelo o fue renombrado — verificar con `fields_get()` en shell.

### `AccessError`
- Falta `ir.model.access.csv` para el modelo; usuario sin permisos; TransientModel sin ACL.

### `ValidationError`
- Un `@api.constrains` o `models.Constraint` falló — leer el mensaje para identificar cuál.

### `QWebException`
- El template QWeb accede a un campo que no existe o no está precargado.
- Solución: agregar el campo como invisible en la vista.

### `ValueError: Wrong value for ir.actions.act_window.view_mode`
- `view_mode` contiene un tipo inválido (ej: 'tree'): corregir a `list`, `form`, `kanban`,
  `calendar`, `graph`, `pivot`.

## Profiling

```bash
# upgrade con profiling (genera .prof); armar sobre el prefijo de $S env:
<odoo-cmd> -d <db> -u <modulo> --stop-after-init --profile
```

---

## Apéndice: resolución manual (SOLO si el wrapper no está/no alcanza)

Los comandos de runtime dependen de cómo corre Odoo. Resolvé estos tres valores desde
`workspace.md` y reemplazá los placeholders:

1. **`<engine>`** = marcador `ODOO_CONTAINER_ENGINE` (`docker`|`podman`; default `docker`).
   ⚠️ No asumas `docker`.
2. **`<odoo-cmd>`** = con marcador `ODOO_CONTAINER`: `<engine> exec <container> odoo`
   (agregar `-it` para interactivo). Sin contenedor (venv): el binario que documente
   `workspace.md` (ej. `<venv>/bin/python <ODOO_CORE>/odoo-bin`).
3. **`<db-cmd>`** = con marcador `ODOO_DB_CONTAINER`: `<engine> exec -i <db_container>`.
   DB local: vacío (psql/pg_dump directo). ⚠️ Si el `db_host` configurado es
   `host.docker.internal`, ese nombre no resuelve desde el host: usar `localhost`.

Ejemplos base: logs `<engine> logs <container> --tail 200`; upgrade
`<odoo-cmd> -d <db> -u <mod> --stop-after-init`; backup
`<db-cmd> pg_dump -U <db_user> <db> | gzip > backup_$(date +%Y%m%d_%H%M%S).sql.gz`.
