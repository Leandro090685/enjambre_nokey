---
name: odoo-data-migration
description: Patrones de migracion de DATOS y scripts de upgrade en Odoo. Carpeta migrations/, funcion migrate(cr, version), pre/post_init_hook, SQL vs ORM, idempotencia y validacion post-upgrade. Cargar al escribir scripts de upgrade o datafixes.
---

# Migración de datos y scripts de upgrade — Odoo

Cuando un cambio de modelo necesita **transformar datos existentes** (renombrar campos, recomputar,
poblar nuevos campos, limpiar), no alcanza con cambiar el código: hay que migrar los datos al hacer
`-u module`. Esto es distinto de migrar **código** entre versiones (eso es `@odoo-migration`): este
skill cubre la transformación de los **datos en la DB**.

## Carpeta `migrations/`

```
module_name/
    migrations/
        <version>/                 # version del modulo, ej. 1.1.0 (matchea el manifest)
            pre-migrate.py         # corre ANTES de cargar el nuevo esquema/XML
            post-migrate.py        # corre DESPUES de actualizar el modulo
            end-migrate.py         # corre al final de TODO el upgrade (todos los modulos)
```

Odoo ejecuta los scripts cuando el `version` del manifest **sube** respecto al instalado. La
carpeta `<version>` debe coincidir con la nueva `version` del manifest (formato `x.x.x`, AGENTS.md).

- **pre**: el esquema viejo todavía existe. Útil para guardar/renombrar columnas antes de que Odoo
  toque la tabla (ej. preservar una columna que se va a recomputar).
- **post**: el modelo nuevo ya está cargado. Útil para poblar campos nuevos vía ORM.

## Firma `migrate(cr, version)`

```python
# -*- coding: utf-8 -*-
# migrations/1.1.0/post-migrate.py
from odoo import api, SUPERUSER_ID


def migrate(cr, version):
    # version = version instalada ANTES del upgrade; None si es instalacion limpia.
    if not version:
        return  # nada que migrar en una instalacion nueva
    env = api.Environment(cr, SUPERUSER_ID, {})
    # Poblar un campo nuevo a partir de datos existentes (vía ORM = respeta computes/constraints).
    records = env["my.model"].search([("new_field", "=", False)])
    for rec in records:
        rec.new_field = rec._compute_new_value()
```

> El script recibe el **cursor crudo** (`cr`), no un `env`. Si necesitás ORM, construí
> `env = api.Environment(cr, SUPERUSER_ID, {})`. Para operaciones masivas, a veces conviene SQL.

## SQL directo vs ORM

| Usar SQL (`cr.execute`) | Usar ORM (`env[...]`) |
|-------------------------|------------------------|
| Volumen grande (miles+ de filas), renombres de columna, updates planos | Lógica de negocio, computes, constraints, campos relacionales |
| Más rápido, no dispara computes | Más seguro y legible; dispara la lógica del modelo |

```python
# SQL para un rename/relleno masivo (rápido, sin lógica):
cr.execute("UPDATE my_model SET new_state = 'done' WHERE old_state = 'closed'")
```

> **Nunca** `cr.commit()` en un script de migración: Odoo maneja el commit del upgrade. Para aislar
> un paso riesgoso usá `with cr.savepoint():`.

## Hooks de instalación (`pre_init_hook` / `post_init_hook`)

Para lógica al **instalar** el módulo (no en cada upgrade), declarar en el manifest (firma v17+:
reciben `env`, no `(cr, registry)` — ver `references/v19_gotchas.md`):

```python
# __manifest__.py
{
    "pre_init_hook": "pre_init_hook",
    "post_init_hook": "post_init_hook",
}

# en __init__.py del modulo
def post_init_hook(env):
    env["my.model"]._backfill_defaults()
```

## Idempotencia y seguridad

- **Idempotente**: el script debe poder correr más de una vez sin duplicar ni romper (filtrá por
  el estado a migrar: `search([("new_field", "=", False)])`, no "todos").
- **Guard de versión**: `if not version: return` evita correr en instalación limpia.
- **Validá post-upgrade**: contá filas afectadas / verificá invariantes; logueá un resumen.
- Probá el upgrade contra una **copia** de la DB de producción antes de aplicarlo (ver flujo de
  upgrade en `debugging-odoo` / `@testing`).

> 🔗 Migrar **código** entre versiones mayores de Odoo (breaking changes) es trabajo de
> `@odoo-migration`. Este skill es para transformar **datos** al subir la `version` del módulo.
