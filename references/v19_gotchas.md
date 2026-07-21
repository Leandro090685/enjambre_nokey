# Breaking changes / gotchas — Odoo 19 (target)

> **Fuente única de verdad** de los breaking changes que más muerden al escribir o migrar
> código con `ODOO_VERSION=19`. Complementa la guía de migración paso a paso
> (`18_to_19.md` y anteriores). El hook `check_breaking_changes.sh` valida automáticamente
> el subconjunto detectable por patrón (ver `patterns/v19.patterns`).
>
> Estos son notas curadas (acumulativas: varios cambios vienen de v16/v17/v18 pero
> siguen aplicando al trabajar contra v19).

## Constraints SQL
- **`_sql_constraints` ELIMINADO** → usar atributo de clase:
  ```python
  _name_unique = models.Constraint("UNIQUE(name)", "El nombre debe ser único.")
  ```
  Ejemplos en `odoo/addons/base/models/res_currency.py`.

## `res.partner`
- **`company_type`** es ahora compute/interface field → **NO usar en domains XML**.
- Usar `is_company` (Boolean) en su lugar.

## `res.users` y grupos
- **`res.users.groups_id` RENOMBRADO** → `group_ids` (explícitos) + `all_group_ids` (compute con implied).
- Para domains de pertenencia a grupo usar `all_group_ids`.
- **`user.user_has_groups('x.y')` DEPRECADO** → usar `self.env.user.has_group('x.y')`.
- Patrón v13 `user.write({'groups_id': [(4, gid)]})` falla en v19 → usar `group_ids`.
- **`res.users.SELF_READABLE_FIELDS`** ahora es `@property` → override con `@property`, no mutar la lista en `__init__`.

## `res.groups`
- **`res.groups.category_id` ELIMINADO** → reemplazado por `privilege_id` (`res.groups.privilege`).
- **`res.groups.users` RENOMBRADO** → `user_ids` (M2M `res_groups_users_rel`, "users explicitly
  in this group"; `odoo/addons/base/models/res_groups.py:17`). El patron clasico de asignar el
  admin a un grupo en data XML falla con `ParseError` en v19:
  ```xml
  <!-- v17 (roto en v19) -->
  <field name="users" eval="[(4, ref('base.user_admin'))]"/>
  <!-- v19 -->
  <field name="user_ids" eval="[Command.link(ref('base.user_admin'))]"/>
  ```
  (Detectado en upgrade real. El propio core lo usa asi: `base/data/res_users_demo.xml:94`.)
  Existe tambien `all_user_ids` (compute, incluye implied) — no usarlo en data.
- Patrón v19:
  ```xml
  <record id="my_privilege" model="res.groups.privilege">
      <field name="name">...</field>
      <field name="category_id" ref="my_module_category"/>
  </record>
  <record id="my_group" model="res.groups">
      <field name="name">...</field>
      <field name="privilege_id" ref="my_privilege"/>
  </record>
  ```

## Modelos eliminados
- **`hr.contract` ELIMINADO** → reemplazado por `hr.version` (cada empleado tiene múltiples versiones temporales con `date_version`). Payroll fields extienden `hr.version`. Refactorizar `_inherit='hr.contract'` y `comodel_name='hr.contract'` a `hr.version`.
- **`hr.expense.sheet` ELIMINADO** (v18) → solo persiste `hr.expense` con submit/approval directo.
- **`hr.employee.base` AbstractModel ELIMINADO** → campos comunes viven en `hr.employee` + `hr.employee.public` + `hr.mixin`.
- **`account.analytic.group` ELIMINADO** (desde v17) → reemplazado por `account.analytic.plan` (sin `company_id`; la compañía vive en `account.analytic.account`).

## `hr.leave` / vacaciones
- **Accrual rearquitecturado** (desde v16): `hr.leave.allocation` perdió `number_per_interval`, `unit_per_interval`, `interval_number`, `interval_unit`, `first_run`, `accrual_limit`. Ahora viven en `hr.leave.accrual.plan.level` + `hr.leave.allocation.accrual_plan_id`.
- **`hr.leave.allocation.allocation_type`**: solo `regular` / `accrual` (sin `fixed_allocation`).
- **`hr.leave.allocation.create` con `state != 'confirm'`** lanza `UserError`. Crear sin `state`, luego `allocation.sudo().action_approve()` (doble llamada si `validation_type='both'`).
- **`hr.leave.type.holiday_type` ELIMINADO** (solo persiste en `hr.leave` y `hr.leave.allocation`).
- **`hr.leave._onchange_leave_dates` / `_get_number_of_days` ELIMINADOS** → lógica centralizada en `_compute_duration` (depends en `date_from`, `date_to`, `holiday_status_id`).
- **`hr.leave.type.name_get` → `_compute_display_name`** (v17+): override con `@api.depends` + `super()` mutando `record.display_name`.
- **`hr.employee._get_work_days_data` → `_get_work_days_data_batch`** (v17+): retorna dict `{emp.id: {'days': n, 'hours': h}}`. Idem `_get_leave_days_data_batch`.
- **View `hr_holidays.hr_leave_allocation_view_form`** reescrita: xpaths v13 (`//div/button/div/span/field[@name='max_leaves']`) NO aplican. Nueva estructura: `div[@id='title']`, `group[@id='full_group']`, `group[@id='alloc_left_col']`, field `number_of_days_display`. Preferir xpaths por `id`/`name`.

## Vistas / QWeb
- **`attrs="{...}"` ELIMINADO** (v17+) → usar atributos directos con expresión Python:
  `invisible="state != 'draft'"`, `readonly="..."`, `required="..."`. Idem `states=`.
- **`<tree>` → `<list>`** (v18+). Requerido en O2M inline y definiciones de list view.
- **`editable=` en `<list>` solo acepta `"top"` o `"bottom"`** — validación RNG server-side
  (`odoo/addons/base/rng/list_view.rng`, choice `top|bottom`): cualquier otro valor
  (`"0"`, `"false"`, `"1"`, …) da `ParseError` al instalar/upgradear y **aborta la carga del
  registry entero**, no solo la vista. No es cosmético: xmllint no lo detecta (el XML es válido),
  revienta recién en el `-u` real. Para una lista embebida read-only el patrón correcto es
  **omitir `editable`** y usar `readonly="1"` en el campo + `create="0" delete="0"` en la `<list>`.
  (Detectado en upgrade real.)
- **Search view `<group expand="0" string="Group By">` ELIMINADO** (v18+). Los `<filter ... context="{'group_by': ...}"/>` van directo en `<search>`.
- **Assets XML (`<template inherit_id="web.assets_backend">`) DEPRECADO** (v17+) → declarar en `__manifest__.py`:
  ```python
  "assets": {"web.assets_backend": ["module/static/src/js/file.js"]}
  ```

## JS / OWL
- **Servicio `rpc` ELIMINADO** (v18+; en v17 todavía existe `rpc_service.js`): `useService('rpc')` lanza
  `Error: Service rpc is not available` y el componente muere al montarse
  (`OwlError: An error occured in the owl lifecycle`). Migrar según el uso:
  - Llamadas a métodos de modelo (`/web/dataset/call_kw`) → servicio `orm`:
    `this.orm = useService('orm')` + `this.orm.call(model, method, args, kwargs)`.
  - Rutas crudas de controller → helper importado: `import { rpc } from '@web/core/network/rpc'`
    y llamar `rpc(route, params)` (ya no es servicio, es función).

## Recordsets / ORM
- **`name_get()` ELIMINADO** (v17+) → override `_compute_display_name()` con `@api.depends(...)` y `super()` mutando `record.display_name`.
- **Hooks de módulo** (`pre_init_hook`/`post_init_hook`/`uninstall_hook`): firma v17+ recibe `(env,)`, NO `(cr, registry)`.
- **Many2one default vacío en compute**: usar `env[comodel].browse()` del modelo EXACTO del field (no del modelo relacionado vía m2o).
- **TransientModel**: requiere `ir.model.access.csv` explícito.
- **Journal entries**: balance check se dispara en flush, no solo en post. Crear moves vía `line_ids=[(0,0,{...})]` en el create, no creando lines sueltas.
- **`hr.employee.public.employee_id`** ya existe nativo en v19 (no requiere compute manual).
