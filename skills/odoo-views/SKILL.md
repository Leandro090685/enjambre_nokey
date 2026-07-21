---
name: odoo-views
description: Patrones de vistas para Odoo. List, form, search, kanban, acciones, menus. Uso de <list>, assets en manifest, y cambios por version. Cargar al crear o modificar vistas.
---

# Patrones de Vistas — Odoo

> **Versión y breaking changes**: la versión objetivo está en `.claude/workspace.md` (`ODOO_VERSION`).
> Los ejemplos abajo asumen v18+/v19; verificá los cambios de tu versión en
> `references/v{ODOO_VERSION}_gotchas.md` (sección Vistas/QWeb). El hook valida los patrones prohibidos.

## Regla #1: `<list>` NO `<tree>`

En v18+ se elimino `<tree>`. Usar siempre `<list>`:
```xml
<list>
    <field name="name"/>
    <field name="date"/>
</list>
```

> Incluso en vistas O2M inline (`One2many`), usar `<list>`.

---

## Vista List (antes tree)

```xml
<record id="my_model_view_list" model="ir.ui.view">
    <field name="name">my.model.view.list</field>
    <field name="model">my.model</field>
    <field name="arch" type="xml">
        <list default_order="sequence, id" decoration-danger="state == 'blocked'" decoration-muted="is_active == False">
            <field name="name"/>
            <field name="partner_id"/>
            <field name="date"/>
            <field name="state" widget="badge"/>
            <field name="amount" sum="Total" widget="monetary"/>
            <field name="company_id" invisible="1"/>
        </list>
    </field>
</record>
```

### Decoration en list
- `decoration-danger` — rojo
- `decoration-warning` — amarillo
- `decoration-success` — verde
- `decoration-info` — azul
- `decoration-muted` — gris claro

---

## Vista Form

```xml
<record id="my_model_view_form" model="ir.ui.view">
    <field name="name">my.model.view.form</field>
    <field name="model">my.model</field>
    <field name="arch" type="xml">
        <form>
            <header>
                <button name="action_confirm" string="Confirm" type="object"
                        invisible="state != 'draft'"
                        class="btn-primary"/>
                <button name="action_done" string="Mark as Done" type="object"
                        invisible="state != 'confirmed'"
                        class="btn-success"/>
                <field name="state" widget="statusbar"/>
            </header>
            <sheet>
                <div class="oe_title">
                    <label for="name" class="oe_edit_only"/>
                    <h1><field name="name" placeholder="Name..."/></h1>
                </div>
                <group>
                    <group>
                        <field name="partner_id"/>
                        <field name="date"/>
                    </group>
                    <group>
                        <field name="user_id"/>
                        <field name="company_id" invisible="1"/>
                    </group>
                </group>
                <notebook>
                    <page string="Lines">
                        <field name="line_ids">
                            <list>
                                <field name="product_id"/>
                                <field name="quantity"/>
                                <field name="price_unit"/>
                            </list>
                        </field>
                    </page>
                </notebook>
            </sheet>
            <div class="oe_chatter">
                <field name="message_follower_ids"/>
                <field name="activity_ids"/>
                <field name="message_ids"/>
            </div>
        </form>
    </field>
</record>
```

---

## Vista Search

```xml
<record id="my_model_view_search" model="ir.ui.view">
    <field name="name">my.model.view.search</field>
    <field name="model">my.model</field>
    <field name="arch" type="xml">
        <search>
            <field name="name"/>
            <field name="partner_id"/>
            <filter name="draft" string="Draft" domain="[('state', '=', 'draft')]"/>
            <filter name="done" string="Done" domain="[('state', '=', 'done')]"/>
            <separator/>
            <filter name="group_by_partner" string="Partner" context="{'group_by': 'partner_id'}"/>
            <filter name="group_by_state" string="State" context="{'group_by': 'state'}"/>
        </search>
    </search>
</record>
```

> **NO usar** `<group expand="0" string="Group By">` — fue eliminado en v18+. Los filtros de agrupacion van directo en `<search>`.

---

## Vista Kanban

```xml
<record id="my_model_view_kanban" model="ir.ui.view">
    <field name="name">my.model.view.kanban</field>
    <field name="model">my.model</field>
    <field name="arch" type="xml">
        <kanban>
            <field name="name"/>
            <field name="state"/>
            <templates>
                <t t-name="kanban-box">
                    <div class="oe_kanban_card">
                        <div class="oe_kanban_content">
                            <strong><field name="name"/></strong>
                            <field name="partner_id"/>
                            <field name="state" widget="badge"/>
                        </div>
                    </div>
                </t>
            </templates>
        </kanban>
    </field>
</record>
```

---

## Assets: declarar en `__manifest__.py`, NO en XML

### INCORRECTO (viejas versiones)
```xml
<template id="assets_backend" inherit_id="web.assets_backend">
    <xpath expr="." position="inside">
        <script type="text/javascript" src="/my_module/static/src/js/my_file.js"/>
    </xpath>
</template>
```

### CORRECTO (v17+, v19)
En `__manifest__.py`:
```python
"assets": {
    "web.assets_backend": [
        "my_module/static/src/js/my_file.js",
        "my_module/static/src/css/my_style.css",
    ],
},
```

---

## Acciones de ventana

```xml
<record id="my_model_action" model="ir.actions.act_window">
    <field name="name">My Models</field>
    <field name="res_model">my.model</field>
    <field name="view_mode">list,form</field>
    <field name="domain">[]</field>
    <field name="context">{'default_user_id': uid}</field>
    <field name="search_view_id" ref="my_model_view_search"/>
</record>
```

### Accion con vista kanban
```xml
<field name="view_mode">kanban,list,form</field>
```

### Accion con filtro por defecto
```xml
<field name="domain">[('state', '=', 'draft')]</field>
```

---

## Menus

```xml
<!-- Menu padre -->
<menuitem id="my_module_menu_root"
          name="My Module"
          sequence="10"/>

<!-- Submenu con accion -->
<menuitem id="my_model_menu"
          name="Items"
          parent="my_module_menu_root"
          action="my_model_action"
          sequence="10"/>
```

---

## Visibilidad/`readonly`/`required` y `domain` en vistas

> **`attrs` se eliminó en v17+/v19.** Usar atributos directos con expresión Python (no listas de
> dominio): `invisible="..."`, `readonly="..."`, `required="..."`.

```xml
<!-- Ocultar campo segun estado -->
<field name="confirmed_date" invisible="state != 'confirmed'"/>

<!-- Requerir campo segun estado -->
<field name="rejection_reason" required="state == 'rejected'"/>

<!-- Solo lectura segun condicion -->
<field name="total" readonly="state != 'draft'"/>

<!-- Domain en Many2one (domain SÍ sigue usando lista) -->
<field name="partner_id" domain="[('is_company', '=', True)]"/>
```

> **NO usar `company_type` en domains** — fue reemplazado por `is_company` en v19.

---

## XML IDs — convención Odoo

`{model}` = nombre del modelo con puntos → guion bajo (`my.model` → `my_model`).

| Tipo | Formato | Ejemplo |
|------|---------|---------|
| Vista (list/form/search/kanban) | `{model}_view_{tipo}` | `my_model_view_form` |
| Acción (principal) | `{model}_action` | `my_model_action` |
| Acción (específica) | `{model}_action_{detalle}` | `my_model_action_child_list` |
| Menú raíz | `{module}_menu_root` | `my_module_menu_root` |
| Menú/submenú | `{model}_menu` / `{model}_menu_{accion}` | `my_model_menu` |
| Grupo | `{module}_group_{nombre}` | `my_module_group_manager` |
| Regla | `{model}_rule_{grupo}` | `my_model_rule_user` |

**El `name` de la vista espeja el XML ID** con guiones bajos → puntos (`my_model_view_form` →
`my.model.view.form`). **Excepción acciones**: nombre descriptivo real (ej. `My Models`).

### Herencia de vistas
La vista que hereda usa el **mismo XML ID** que la original (el prefijo de módulo evita el choque) y
agrega `.inherit.<module>` al `name`:
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

> Detalle completo de convenciones (estructura de módulo, estilo Python, XML) en `AGENTS.md`.
