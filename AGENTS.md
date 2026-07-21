# AGENTS.md — Nokey · Odoo 19

Este archivo describe convenciones y reglas que **TODO agente de IA** (Aider, Claude Code, Cursor, Codex, etc.) debe respetar al trabajar en este workspace.

> 🌎 **Entorno y versión**: este archivo es **agnóstico de versión y de entorno**. Cómo está armado
> el workspace —versión de Odoo (`ODOO_VERSION`), paths (root, `odoo/`, `enterprise/`, addons),
> organización de clientes, y si corre en Docker o venv— se describe **una sola vez** en
> `.claude/workspace.md` (por desarrollador, ver `.claude/workspace.example.md`). Leé `workspace.md`
> para ubicarte; los detalles puntuales (contenedor, DB) se resuelven en runtime.

## 🏢 Identidad
- **Empresa**: Sunra
- **Versión Odoo objetivo**: la definida en `ODOO_VERSION` (`workspace.md`).
- **Licencia por defecto de módulos custom**: **LGPL-3**
- **Autor por defecto**: `Sunra` — website `https://github.com/sunraargsh`.

## 📂 Rutas del workspace

El root y **qué repos concretos existen** (clientes, productos/compartidos, paths, contenedor) los
describe `workspace.md` — única fuente de verdad del entorno. Ahí se declaran (opcionalmente) los
**paths con nombre** que agentes y hooks resuelven sin adivinar:

- **Handles** `NOMBRE: path` — un repo por línea (relativo al root, o absoluto con `/`/`~`). Ej.
  `ODOO_CORE`, `ODOO_ENTERPRISE`, `ODOO_CUSTOM_<cliente>`.
- **Listas (categorías)** — agrupan handles (o paths). Es lo que se referencia en agents/skills:
  - `CORE_ROOTS` → core/enterprise (se **excluyen** de validación; default `odoo enterprise`).
  - `CLIENT_ADDONS` → customizaciones por cliente.
  - `PRODUCT_ADDONS` → productos / repos compartidos.
  - `ADDONS_ROOTS` (derivado/legacy) = `CLIENT_ADDONS ∪ PRODUCT_ADDONS`; default `extra-addons`.

> Todo es **opcional**: sin declarar nada, los módulos custom se detectan por estructura (su
> `__manifest__.py`, excluyendo core/enterprise) y rigen los defaults (`odoo enterprise`,
> `extra-addons`). En agents/skills se usan las **categorías** (`CLIENT_ADDONS`, `PRODUCT_ADDONS`,
> `<ADDONS_ROOT>`, `<modulo_path>`), nunca nombres de repos: el inventario concreto vive solo en `workspace.md`.

> ⚠️ **NUNCA** modificar archivos de core/enterprise (`CORE_ROOTS`). Heredar siempre vía `_inherit`.

> 🔒 **Política de secretos (per-dev)**: hoy el enjambre no requiere secretos. Si en el futuro
> hiciera falta alguno (tokens, passwords, API keys), **NUNCA** vive dentro del repo del enjambre —
> **ni siquiera en archivos gitignored** como `settings.local.json`. Va en un **archivo local fuera
> del repo**, en el HOME del dev, cuyo path se declara con el marcador `NOKEY_SECRETS_FILE` en
> `workspace.md` (`chmod 600`, formato `KEY=value`).

## 🌐 Idioma y convenciones
- Código (modelos, campos, métodos, variables, archivos): **inglés**
- Comentarios en código: **español**
- Strings de UI traducibles con `_()`: **inglés**
- Seguir https://www.odoo.com/documentation/\{ODOO_VERSION\}.0/contributing/development/coding_guidelines.html

## 📐 Encabezados / pies de archivo (obligatorios)

### Python (`*.py`)
- Primera línea: `# -*- coding: utf-8 -*-`
- Última línea: `# vim:expandtab:smartindent:tabstop=4:softtabstop=4:shiftwidth=4:`

### XML (`*.xml`)
- Primera línea: `<?xml version="1.0" encoding="utf-8"?>`
- Última línea: `<!-- vim:expandtab:smartindent:tabstop=4:softtabstop=4:shiftwidth=4-->`

### Sin banner de licencia en los archivos (v17+)
- El encabezado de un archivo es **solo** la línea de coding (`.py`) / declaración XML, el contenido,
  y el modeline `vim` al final. **NO** incluir el bloque de licencia AGPL/GPL (el banner
  `####…####` con el texto *"This program is free software … GNU Affero General Public License …"*,
  o su equivalente en comentario `<!-- … -->` en XML).
- La licencia se declara **una sola vez** en `__manifest__.py` (campo `license`). Repetir el banner
  en cada `.py`/`.xml` es ruido.

### Plantilla Python (`models/*.py`)

```python
# -*- coding: utf-8 -*-
import time

from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class MyModel(models.Model):
    _name = "my.model"
    _description = "My Model"

    # Campo de ejemplo
    name = fields.Char(string="Name", required=True)
    is_active = fields.Boolean(string="Is Active", default=True, help="Indicates if the record is active.")
    # Todos los raise de errores deben usar _() para traducción y deben estar en inglés, también los strings de los campos y help.

    @api.constrains("name")
    def _check_name(self):
        # Validación de nombre
        for rec in self:
            if not rec.name or not rec.name.strip():
                raise ValidationError(_("The name cannot be empty."))

    def _process_data(self, validated_data):
        """
        Procesar datos validados.

        :param validated_data: Lista de diccionarios con datos validados
        :type validated_data: list
        :return: dict con resultado del procesamiento
        :rtype: dict
        """

# vim:expandtab:smartindent:tabstop=4:softtabstop=4:shiftwidth=4:
```

### Plantilla XML (`views/*.xml`)

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Vista list de ejemplo. XML ID = {model}_view_{tipo}; name espeja el id con puntos. -->
    <record id="my_model_view_list" model="ir.ui.view">
        <field name="name">my.model.view.list</field>
        <field name="model">my.model</field>
        <field name="arch" type="xml">
            <list>
                <field name="name"/>
                <field name="is_active"/>
            </list>
        </field>
    </record>

    <!-- Acción y menú. Acción: XML ID = {model}_action; name = nombre descriptivo real. -->
    <record id="my_model_action" model="ir.actions.act_window">
        <field name="name">My Models</field>
        <field name="res_model">my.model</field>
        <field name="view_mode">list,form</field>
    </record>

    <menuitem id="my_model_menu_root" name="My Models" sequence="10"/>
    <menuitem id="my_model_menu" name="Items" parent="my_model_menu_root" action="my_model_action" sequence="10"/>
</odoo>
<!-- vim:expandtab:smartindent:tabstop=4:softtabstop=4:shiftwidth=4-->
```

## 📦 Manifest (`__manifest__.py`)
- `name`: en **inglés**, coincide con el nombre técnico del módulo.
- Resto del manifest (`summary`, `description`, etc.): en **español**.
- Incluir: `author="Sunra"`, `website="https://github.com/sunraargsh"`, `license="LGPL-3"`.
- `version`: formato **`x.x.x` simple** (ej. `1.0.0`), **sin** prefijo de serie de Odoo — Odoo
  antepone la serie solo. **No** usar `19.0.1.0.0` ni similares (desaconsejado; y `{serie}.1.0.0`
  deja el módulo uninstallable). En módulos gestionados por SDD, este `version` debe coincidir
  siempre con la `Version` de la spec (ver skill `sdd-specification`).

```python
# -*- coding: utf-8 -*-
{
    "name": "module_technical_name",
    "version": "1.0.0",
    "summary": "Resumen breve en español",
    "description": """
Descripción en español.
- Objetivo principal
- Funcionalidades clave
    """,
    "category": "Custom",
    "author": "Sunra",
    "website": "https://github.com/sunraargsh",
    "license": "LGPL-3",
    "depends": ["base"],
    "data": [],
    "assets": {
        # "web.assets_backend": [
        #     "module_technical_name/static/src/js/*.js",
        # ],
    },
    "installable": True,
    "application": False,
    "auto_install": False,
}
# vim:expandtab:smartindent:tabstop=4:softtabstop=4:shiftwidth=4:
```

## 🧱 Arquitectura y prácticas
- Preferir `_inherit` / `inherit_id` y siempre llamar a `super()`.
- Decoradores correctos: `@api.depends`, `@api.constrains`, `@api.onchange`.
- Evitar `sudo()` salvo necesidad clara y justificada (seguridad, flujo).
- Respetar ACL (`ir.model.access.csv`) e `ir.rule`.
- Mensajes de validación con `_()` (UI en inglés).
- Evitar N+1: usar `read_group`, `search_read`, `compute store=True`.
- Visibilidad/lógica simple en XML (`domain`, y atributos directos `invisible`/`readonly`/`required`
  con expresión Python — recordá que `attrs` se eliminó en v17+) cuando aplique.
- No hardcodear lógica de negocio en vistas.
- **Nunca** llamar `cr.commit()`: el framework hace commit por llamada RPC. Si alguna vez hay razón
  justificada, agregar un comentario explícito que explique por qué es necesario, por qué es correcto
  y por qué no rompe la transacción.
- Para aislar operaciones riesgosas usar **savepoints**, no commits:
  ```python
  try:
      with self.env.cr.savepoint():
          risky_operation()
  except SomeError:
      handle_error()
  ```
- `ensure_one()` al inicio de todo método de acción (`action_*`) que opere sobre un único registro.
- **Propagar contexto** con `records.with_context(key=value).method()`. Prefijar las claves de
  contexto propias con el nombre del módulo para aislar su impacto (ej. `mymod_skip_validation`).
  Cuidado con `default_<campo>`: setea el default en **todo** modelo que tenga ese campo durante la
  cadena de llamada.

## 📁 Estructura de módulo y reglas de archivos

```
module_name/
    __init__.py
    __manifest__.py
    models/
        __init__.py
        <model_name>.py            # un archivo por modelo (o set de modelos muy relacionados)
        res_partner.py             # los modelos heredados van en su propio archivo
    views/
        <model_name>_views.xml     # un archivo por modelo
        <model_name>_templates.xml
        <module_name>_menus.xml    # menús principales (opcional, solo si hacen falta)
        assets.xml                 # declaración de bundles JS/CSS (si aplica)
    security/
        ir.model.access.csv
        <module>_groups.xml
        <model>_security.xml
    data/
        <model>_data.xml
    demo/
        <model>_demo.xml
    controllers/
        <module_name>.py           # un solo archivo (main.py está deprecado)
    wizard/
        <transient>.py             # TODA la lógica de wizard en UN solo .py
        <transient>_views.xml      # TODAS las vistas de wizard en UN solo .xml
    report/
        <model>_report.py          # reportes estadísticos basados en SQL view
        <model>_report_views.xml
        <model>_reports.xml        # acciones de reporte QWeb imprimible / paperformat
        <model>_templates.xml      # templates QWeb del reporte
    static/
        description/               # index.html + icon (documentación obligatoria)
        src/{js,scss,css,xml,img}/
        lib/                       # librerías JS de terceros (una subcarpeta cada una)
```

**Reglas de archivos y carpetas:**
- **Un archivo por modelo** (o set de modelos muy relacionados), tanto en `models/` como en `views/`.
  Los modelos Odoo heredados van en su **propio** archivo (ej. `res_partner.py` / `res_partner_views.xml`).
- **Excepción wizards**: toda la lógica de un wizard va en **un solo** `.py` y todas sus vistas en
  **un solo** `.xml`, ambos dentro de `wizard/`.
- El archivo de **menús** se llama `<module_name>_menus.xml` (ej. `sale_menus.xml`).
- **Controllers**: usar `<module_name>.py`; el viejo `main.py` está deprecado. Para heredar un
  controller de otro módulo: `<modulo_heredado>.py` (ej. `portal.py`).
- **Nombres de archivo**: solo `[a-z0-9_]` (minúsculas, números, guion bajo).
- **Permisos**: carpetas 755, archivos 644.
- **Nunca linkear assets externos** (imágenes, librerías): copiarlos al repositorio.

## 🐍 Estilo de código Python

### Orden de imports
```python
# 1: stdlib (alfabético)
import base64
import re
from datetime import datetime

# 2: imports de Odoo (ASCIIbético)
from odoo import Command, _, api, fields, models
from odoo.exceptions import UserError, ValidationError
from odoo.tools.safe_eval import safe_eval

# 3: imports de otros addons Odoo (poco frecuente)
from odoo.addons.website.models.website import slug
```

### Orden de definición dentro del modelo
1. Atributos privados (`_name`, `_description`, `_inherit`, `_order`, …)
2. Métodos default y `default_get`
3. Declaración de campos
4. Métodos compute / inverse / search (en el mismo orden que los campos)
5. Métodos de selection (`_selection_<campo>`)
6. Constraints (`@api.constrains`) y onchange (`@api.onchange`)
7. CRUD (`create`, `write`, `unlink`, `name_get`, `name_search`, …)
8. Métodos de acción (`action_*`)
9. Métodos de negocio (privados, `_*`)

### Naming (canon — usar siempre)

| Tipo | Convención | Ejemplo |
|------|------------|---------|
| Clase Python | PascalCase, espeja `_name` (puntos → PascalCase) | `sale.order` → `SaleOrder` |
| Modelo regular | singular, notación con puntos, prefijo del módulo | `sale.order`, `res.partner` |
| Modelo transient (wizard) | `<base>.<accion>` — **preferir evitar la palabra "wizard"** | `account.invoice.make` |
| Modelo report (SQL view) | `<base>.report.<accion>` | `sale.order.report.analysis` |
| Many2one | sufijo `_id` | `partner_id` |
| X2many | sufijo `_ids` | `order_line_ids` |
| Compute | `_compute_<campo>` | `_compute_amount_total` |
| Search | `_search_<campo>` | `_search_display_name` |
| Default | `_default_<campo>` | `_default_date` |
| Selection | `_selection_<campo>` | `_selection_state` |
| Constraint | `_check_<nombre>` | `_check_date_order` |
| Onchange | `_onchange_<campo>` | `_onchange_partner_id` |
| Acción | `action_<nombre>` | `action_confirm` |
| Método privado | `_<nombre>` | `_prepare_invoice` |

### Naming de variables
```python
Partner = self.env['res.partner']     # CamelCase para referencias a modelo
partners = Partner.browse(ids)        # minúscula para recordsets
partner = Partner.search([...], limit=1)
partner_id = partner.id               # _id / _ids = IDs crudos (int / list[int])
partner_ids = partners.ids            # NO guardar un record en una variable *_id
```

### Traducciones (`_()`)
```python
# BIEN: string plano
raise UserError(_('This record is locked!'))
# BIEN: una variable con %s
error = _('Record %s cannot be modified!', record.name)
# BIEN: varias variables -> usar %(nombre)s para ayudar al traductor
error = _("Answer to question %(title)s is not valid.", title=question)
# MAL: formatear fuera de _()
error = _('Record %s cannot be modified!') % record.name
# MAL: concatenar / strings dinámicos dentro de _()
error = _("'" + question + "' is invalid")
```
Preferir `%` sobre `.format()` en código Odoo.

### Buenas prácticas generales
- Favorecer **legibilidad** sobre concisión; evitar cleverness del lenguaje.
- Usar métodos de colección del ORM (`filtered`, `mapped`, `sorted`): más legibles y rápidos.
- Los recordsets/colecciones son booleanos: `if records:` (no `if len(records):`).
- Preferir list/dict comprehensions sobre `map`/`filter` con lambdas.
- `dict.setdefault()` para simplificar appends condicionales a valores de dict.
- Evitar generators y decoradores propios: usar solo los de la API de Odoo.

## 🧩 Convenciones XML

### Formato
- En `<record>`: el atributo `id` va **antes** de `model`.
- En `<field>`: primero `name`, luego el valor (`eval` o contenido), luego otros atributos por
  importancia (`widget`, `options`, …).
- Agrupar los `<record>` por modelo dentro del archivo.
- Preferir los tags cortos **`<menuitem>`** y **`<template>`** sobre la notación `<record>`.
- Usar `<data noupdate="1">` solo en archivos **mixtos** (algunos updatables, otros no). Si **todo**
  el archivo es no-updatable, poner `noupdate="1"` en el tag `<odoo>` y omitir `<data>`.

### XML IDs (convención Odoo)

`{model}` = nombre del modelo con puntos → guion bajo (`my.model` → `my_model`).

| Tipo | Patrón | Ejemplo |
|------|--------|---------|
| Vista | `{model}_view_{tipo}` | `sale_order_view_form` |
| Acción (principal) | `{model}_action` | `sale_order_action` |
| Acción (específica) | `{model}_action_{detalle}` | `sale_order_action_child_list` |
| Menú (con acción) | `{model}_menu` | `sale_order_menu` |
| Submenú | `{model}_menu_{accion}` | `sale_order_menu_confirm` |
| Grupo | `{module}_group_{nombre}` | `sale_group_manager` |
| Regla | `{model}_rule_{grupo}` | `sale_order_rule_user` |

### El campo `name` espeja el XML ID
Para **vistas**, `name` = el XML ID con guiones bajos → puntos:
```xml
<record id="sale_order_view_form" model="ir.ui.view">
    <field name="name">sale.order.view.form</field>
</record>
```
**Excepción — acciones**: usar un nombre descriptivo real (ej. `Sales Orders`).

### Herencia de vistas
La vista que hereda usa el **mismo XML ID** que la original (el prefijo de módulo evita el choque)
y agrega `.inherit.<module>` al `name`:
```xml
<record id="sale_order_view_form" model="ir.ui.view">
    <field name="name">sale.order.view.form.inherit.my_module</field>
    <field name="inherit_id" ref="sale.sale_order_view_form"/>
    <field name="arch" type="xml">
        <field name="partner_id" position="after">
            <field name="my_field"/>
        </field>
    </field>
</record>
```
Las **primary views** nuevas (`mode="primary"`) no llevan el sufijo `.inherit`.

## ✂️ Reglas de edición (diff mínimo)
- **Nunca** reformatear un archivo existente solo para aplicar estas guías: el estilo del archivo
  original tiene prioridad y los diffs se mantienen mínimos.
- Aplicar las guías **solo al código que estás cambiando activamente**.
- Si necesitás mover código, hacelo en un cambio (commit) dedicado, separado del cambio funcional.
- Excepciones PEP8 toleradas: E501 (largo de línea), E301/E302 (líneas en blanco).
- **Minimal footprint** (complementa el diff mínimo): *diff mínimo* = no reformatear lo existente;
  *minimal footprint* = no **sobre-construir** lo nuevo. Antes de escribir lógica nueva, reusá
  core/framework/dependencia existente y elegí el menor cambio que cumpla. Fuente única de esta
  disciplina: skill `minimal-footprint` (incluye los NO-negociables que nunca se recortan).

## 🧪 Tests
- **NO escribir tests** salvo que (a) se pidan explícitamente, o (b) el repo los requiera vía
  **política por repo**: archivo **`.swarm.conf`** en la raíz del repo de addons (committeado,
  formato `KEY=value`; plantilla en `.claude/assets/templates/swarm.conf.tmpl`). Sin archivo o sin
  la clave → no requeridos (default). Hay **dos ejes independientes** (uno, otro, ambos o ninguno):
  - **`TESTS=required`** → tests **backend** (unit/integración Python): `TransactionCase` /
    `SingleTransactionCase` / `HttpCase` para modelos, computes, constraints, controllers.
  - **`E2E=required`** → tests **e2e de UI** con **Tours de Odoo** (`HttpCase.start_tour` + tour JS
    registrado en `web_tour.tours`). Solo para módulos con un **flujo de UI troncal**
    (portal/website/ecommerce, JS en `static/src`, controllers) — no todo módulo lleva tour.
- **Cuando `TESTS=required` aplica:**
  - Módulo tocado **sin** `tests/` → agregar en la misma tarea la suite inicial de sus **flujos
    troncales** (sin exagerar: happy paths + constraints clave, no matriz exhaustiva de edge cases).
  - Módulo **con** tests y el cambio agrega/modifica un flujo troncal → agregar/ajustar los tests de
    ese flujo (anti-drift, igual que la documentación). Cambios menores (un string, un label) → nada.
- **Cuando `E2E=required` aplica** (por juicio, no universal): si el cambio toca un flujo de UI
  troncal de un módulo con UI y ese flujo no tiene tour → agregar/ajustar un Tour de ese flujo.
  Un módulo backend puro (sin controllers ni JS) **no** exige e2e.
  - ⚠️ Los tours corren en un **Chrome/chromium real en el contenedor** — es un **prerequisito que
    se asegura antes de correr**: si falta, @testing avisa y (con OK del usuario) lo instala
    (`odoo_runtime.sh chrome-install`) para que los tours **se ejecuten de verdad**. Odoo saltea el
    tour si no hay Chrome; un e2e **skipped no cuenta como pasado** (gate no satisfecho, no un "verde").
- Los tests escritos (backend y e2e) **se corren** antes de cerrar la tarea (skill `debugging-odoo` /
  `odoo_runtime.sh test` · `run-tests`). El alcance detallado está en el skill `odoo-tests`.
- **Cómo escribirlos** (pedidos o por política): clase con `@tagged(...)`, heredar de la base correcta
  (`TransactionCase` = savepoint por test, `SingleTransactionCase` = compartido, `HttpCase` =
  HTTP/controllers **y tours e2e**), datos en `setUpClass`. Tags: `at_install` / `post_install`
  (excluir con `-tag`). Ver skill `debugging-odoo` para ejecutarlos en Docker.

## 🧰 Forma esperada de las respuestas

Al recibir una especificación:
1. **Analiza el contexto** (revisa primero el código base/enterprise/custom relevante)
2. **Enumera archivos y rutas completas** a crear/modificar (ej: `<ADDONS_ROOT>/odoo_customization_<cliente>/module/models/invoice_validation.py`, donde `<ADDONS_ROOT>` sale de `workspace.md`)
3. **Explica brevemente la lógica** elegida y por qué sigue estándares Odoo
4. **Entrega código completo y funcional** (sin tests, salvo pedido explícito o política del repo — ver sección Tests), con encabezados/pies y estilo definidos
5. **Incluye pasos de validación manual** cuando aplique

## 🚫 Restricciones
- No mezclar código entre proyectos de customización.
- No introducir dependencias externas no justificadas.
- No tocar core ni enterprise.
- La documentación (`README.md` + `static/description/index.html`) es **obligatoria** para todo módulo. Ver sección "Documentación de módulos y repos (obligatoria)".

---

## ⚠️ Breaking Changes

> **Fuente única de verdad: `.claude/references/`** — no hay listas de breaking changes
> copiadas en este archivo ni en los agentes/skills. Para tu `ODOO_VERSION` (`workspace.md`)
> consultá, en orden:
>
> 1. **Salto de migración**: `references/{ODOO_VERSION-1}_to_{ODOO_VERSION}.md` (y los saltos
>    anteriores si venís de una versión más vieja). Ej. v19 → `references/18_to_19.md`.
> 2. **Gotchas curados**: `references/v{ODOO_VERSION}_gotchas.md` — los cambios que más
>    muerden (constraints, `res.groups`/`res.users`, `hr.contract`/`hr.version`, `hr.leave`,
>    vistas `<tree>`→`<list>`, ORM, etc.). Ej. v19 → `references/v19_gotchas.md`.
> 3. **Patrones comunes**: `references/common_patterns.md`.
>
> El hook `check_breaking_changes.sh` valida automáticamente el subconjunto detectable por
> patrón (`references/patterns/v{ODOO_VERSION}.patterns`) y **bloquea** el Write/Edit si
> encuentra un patrón prohibido. Soportar una versión nueva = agregar sus archivos en
> `references/` (incluido `patterns/v{N}.patterns`), sin tocar este documento ni el hook.

## 🤖 Arquitectura del enjambre

Cómo se coordinan agentes, procedimientos y orquestador (flujo, **protocolo de fallback**, **formato
de handoff**, tabla de agentes y cuándo invocarlos) **no se documenta acá**: vive en `CLAUDE.md`
(comportamiento del orquestador) y en `ENJAMBRE.md` (arquitectura para humanos). Este documento es
**solo convenciones de código** — no lo dupliques.

## 📂 Documentación de módulos y repos (obligatoria)

> Esto es una **convención** (qué documentación debe existir). El *cómo* operativo —explorar repos,
> detectar módulos, generar la doc— es trabajo de los agentes (`@researcher`, `@client-context`,
> `@module-index-html`), no de este archivo.

Los módulos custom se agrupan en repos de addons bajo `<ADDONS_ROOT>`. La documentación vive en dos
niveles:

1. **`README.md` en la raíz del repo** — resumen general + índice de módulos: para que un agente sepa qué repo consultar.
2. **`README.md` dentro de cada módulo** — documentación técnica detallada: para tener contexto completo al trabajar ese módulo.

**Regla obligatoria: TODO módulo debe tener documentación. Al crear o modificar un módulo, generar/actualizar la documentación correspondiente.**

| Acción | Documentación a crear/actualizar |
|--------|----------------------------------|
| Nuevo módulo | `README.md` del repositorio + `README.md` del módulo + `static/description/index.html` |
| Trabajar en módulo sin documentación | Crear `README.md` del módulo + `static/description/index.html` **antes de modificar código** |
| Modificar módulo existente | Actualizar `README.md` del módulo e `index.html` si cambia funcionalidad |
| Eliminar módulo | Eliminar entrada del `README.md` del repositorio |

> ⚠️ **NUNCA trabajar en un módulo sin documentación.** Si el módulo no tiene `README.md` ni `static/description/index.html`, invocar `@module-index-html` para generarlos **antes** de empezar a modificar código. La documentación debe existir incluso en módulos simples.

### La documentación es también fuente de contexto (loop bidireccional)

La doc no es solo un artefacto de salida: es la **primera fuente de contexto** al trabajar un
módulo. Los agentes que necesitan entender un módulo (@client-context, @code-dev, @sdd-generate)
**leen el `README.md` del módulo ANTES de grepear el código** — es el resumen curado (objetivo de
negocio, modelos, seguridad, integraciones, gotchas) y orienta más rápido que el código crudo. El
`README.md` raíz del repo da el panorama e índice de módulos.

Esto cierra el loop: el código alimenta la doc (se escribe/actualiza al cambiar), y la doc alimenta
el contexto (se lee al empezar). Por eso la **regla anti-drift** es crítica: si un cambio altera
funcionalidad visible, actualizar `README.md` e `index.html` es **obligatorio en la misma tarea**
—una doc desactualizada no solo confunde al humano, envenena el contexto del próximo agente.
