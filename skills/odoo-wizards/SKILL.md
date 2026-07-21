---
name: odoo-wizards
description: Patrones de wizards y TransientModel en Odoo. Wizards de un paso, multi-paso con estados, limpieza automatica, y patrones comunes de interaccion.
---

# Patrones de Wizards — Odoo

> **Naming (guía blanda)**: para el `_name` del `TransientModel` se **prefiere** la forma
> `<modelo_base>.<accion>` y **evitar la palabra "wizard"** (ej. `account.invoice.make`,
> `my.model.confirm`, no `account.invoice.wizard`). No es obligatorio, pero alinea con Odoo. La
> **carpeta** sigue llamándose `wizard/` y toda la lógica va en un solo `.py` + un solo `.xml`.

## TransientModel — modelo temporal

Los wizards usan `TransientModel` en lugar de `Model`. Sus registros se limpian automaticamente.

```python
# -*- coding: utf-8 -*-
from odoo import api, fields, models, _

class MyModelExport(models.TransientModel):
    _name = "my.model.export"
    _description = "My Model Export"

    date_from = fields.Date(string="From Date", required=True)
    date_to = fields.Date(string="To Date", required=True)
    partner_id = fields.Many2one("res.partner", string="Partner")

    def action_process(self):
        self.ensure_one()
        # Logica del wizard
        return {"type": "ir.actions.act_window_close"}
```

> **CRITICO v19**: TransientModel requiere `ir.model.access.csv` explicito.

---

## Wizard simple (un paso)

### Modelo
```python
class MyModelConfirm(models.TransientModel):
    _name = "my.model.confirm"
    _description = "My Model Confirm"

    reason = fields.Text(string="Reason")

    def action_confirm(self):
        self.ensure_one()
        active_ids = self.env.context.get("active_ids", [])
        records = self.env["my.model"].browse(active_ids)
        records.write({"state": "confirmed", "reason": self.reason})
        return {"type": "ir.actions.act_window_close"}
```

### Vista
```xml
<record id="my_model_confirm_view_form" model="ir.ui.view">
    <field name="name">my.model.confirm.view.form</field>
    <field name="model">my.model.confirm</field>
    <field name="arch" type="xml">
        <form>
            <group>
                <field name="reason"/>
            </group>
            <footer>
                <button name="action_confirm" string="Confirm" type="object" class="btn-primary"/>
                <button string="Cancel" class="btn-secondary" special="cancel"/>
            </footer>
        </form>
    </field>
</record>
```

### Accion (para abrir desde boton o menu)
```xml
<record id="my_model_confirm_action" model="ir.actions.act_window">
    <field name="name">Confirm Records</field>
    <field name="res_model">my.model.confirm</field>
    <field name="view_mode">form</field>
    <field name="target">new</field>
</record>
```

> `target="new"` abre el wizard como popup/modal.

---

## Wizard multi-paso con estados

```python
class MyModelSetup(models.TransientModel):
    _name = "my.model.setup"
    _description = "My Model Setup"

    state = fields.Selection([
        ("step1", "Select Partner"),
        ("step2", "Enter Details"),
        ("step3", "Confirm"),
    ], string="State", default="step1")

    partner_id = fields.Many2one("res.partner", string="Partner")
    amount = fields.Float(string="Amount")

    def action_next_step2(self):
        self.state = "step2"
        return self._reopen_wizard()

    def action_next_step3(self):
        self.state = "step3"
        return self._reopen_wizard()

    def action_back(self):
        if self.state == "step2":
            self.state = "step1"
        elif self.state == "step3":
            self.state = "step2"
        return self._reopen_wizard()

    def action_confirm(self):
        self.ensure_one()
        # Ejecutar logica final
        return {"type": "ir.actions.act_window_close"}

    def _reopen_wizard(self):
        return {
            "type": "ir.actions.act_window",
            "res_model": self._name,
            "res_id": self.id,
            "view_mode": "form",
            "target": "new",
        }
```

### Vista con estados

> `attrs` se eliminó en v17+/v19: usar atributos directos `invisible="..."` con expresión Python.

```xml
<record id="my_model_setup_view_form" model="ir.ui.view">
    <field name="name">my.model.setup.view.form</field>
    <field name="model">my.model.setup</field>
    <field name="arch" type="xml">
        <form>
            <field name="state" invisible="1"/>
            <!-- Paso 1 -->
            <group invisible="state != 'step1'">
                <field name="partner_id"/>
            </group>
            <!-- Paso 2 -->
            <group invisible="state != 'step2'">
                <field name="amount"/>
            </group>
            <!-- Paso 3: Confirmacion -->
            <group invisible="state != 'step3'">
                <p>Confirm partner <strong><field name="partner_id"/></strong> with amount <strong><field name="amount"/></strong>?</p>
            </group>
            <footer>
                <!-- Paso 1 -->
                <button name="action_next_step2" string="Next" type="object"
                        invisible="state != 'step1'" class="btn-primary"/>
                <!-- Paso 2 -->
                <button name="action_back" string="Back" type="object"
                        invisible="state != 'step2'" class="btn-secondary"/>
                <button name="action_next_step3" string="Next" type="object"
                        invisible="state != 'step2'" class="btn-primary"/>
                <!-- Paso 3 -->
                <button name="action_back" string="Back" type="object"
                        invisible="state != 'step3'" class="btn-secondary"/>
                <button name="action_confirm" string="Confirm" type="object"
                        invisible="state != 'step3'" class="btn-primary"/>
            </footer>
        </form>
    </field>
</record>
```

---

## Abrir wizard desde un boton en form view

```xml
<button name="%(my_module.my_model_confirm_action)d"
        string="Confirm"
        type="action"
        context="{'active_ids': [id], 'active_model': 'my.model'}"/>
```

---

## `default_get` para precargar datos

```python
@api.model
def default_get(self, fields_list):
    defaults = super().default_get(fields_list)
    active_ids = self.env.context.get("active_ids", [])
    if active_ids:
        record = self.env["my.model"].browse(active_ids[0])
        defaults["partner_id"] = record.partner_id.id
    return defaults
```

---

## Wizard que ejecuta accion y muestra resultado

```python
def action_generate(self):
    self.ensure_one()
    records = self.env["my.model"].search([
        ("date", ">=", self.date_from),
        ("date", "<=", self.date_to),
    ])
    # Crear registros o retornar accion
    records.action_process()
    return {"type": "ir.actions.act_window_close"}
```

---

## Checklist de wizards

- [ ] Usa `models.TransientModel`
- [ ] `_name` con forma `<base>.<accion>` (preferir evitar "wizard")
- [ ] `_description` presente
- [ ] `ir.model.access.csv` tiene entrada para el wizard
- [ ] La vista usa `target="new"` en la accion
- [ ] El footer tiene boton Cancel (`special="cancel"`)
- [ ] `self.ensure_one()` al inicio de metodos de accion
- [ ] `active_ids` se usa via `self.env.context.get()`
- [ ] Visibilidad con atributos directos (`invisible="..."`), NO `attrs`
- [ ] Para multi-paso, se usa `_reopen_wizard()` para refrescar la vista
