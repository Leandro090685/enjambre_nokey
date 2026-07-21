---
name: odoo-orm-patterns
description: Patrones de ORM para Odoo. Campos, metodos compute, constrains, onchange, CRUD, busqueda, prevencion de N+1. Usar al implementar modelos o logica de negocio.
---

# Patrones ORM — Odoo

## Tipos de campos

### Campos basicos
```python
name = fields.Char(string="Name", required=True, index=True)
code = fields.Char(string="Code", size=10)
description = fields.Text(string="Description")
is_active = fields.Boolean(string="Is Active", default=True)
sequence = fields.Integer(string="Sequence", default=10)
amount = fields.Float(string="Amount", digits=(16, 2))
price = fields.Monetary(string="Price", currency_field="currency_id")
date_from = fields.Date(string="From Date")
date_to = fields.Datetime(string="To Date")
state = fields.Selection([
    ("draft", "Draft"),
    ("confirmed", "Confirmed"),
    ("done", "Done"),
], string="State", default="draft")
```

### Campos relacionales
```python
partner_id = fields.Many2one("res.partner", string="Partner", ondelete="restrict")
line_ids = fields.One2many("sale.order.line", "order_id", string="Lines")
category_ids = fields.Many2many("product.category", string="Categories")
user_id = fields.Many2one("res.users", string="User", default=lambda self: self.env.user)
company_id = fields.Many2one("res.company", string="Company", default=lambda self: self.env.company)
```

### Campos computados
```python
@api.depends("line_ids.price_subtotal")
def _compute_total(self):
    for rec in self:
        rec.total = sum(rec.line_ids.mapped("price_subtotal"))

total = fields.Float(string="Total", compute="_compute_total", store=True)
```

### Campos relacionados (related)
```python
partner_email = fields.Char(string="Partner Email", related="partner_id.email", readonly=True)
company_currency = fields.Many2one("res.currency", related="company_id.currency_id")
```

---

## Constraints

### `models.Constraint` (NUEVO en v19 — reemplaza `_sql_constraints`)
```python
_name_unique = models.Constraint(
    "UNIQUE(name, company_id)",
    "El nombre ya existe para esta compania."
)
```

### `@api.constrains`
```python
@api.constrains("date_from", "date_to")
def _check_dates(self):
    for rec in self:
        if rec.date_from and rec.date_to and rec.date_from > rec.date_to:
            raise ValidationError(_("Date From cannot be after Date To."))
```

---

## Metodos compute, inverse, search

### Compute basico
```python
@api.depends("first_name", "last_name")
def _compute_display_name(self):
    for rec in self:
        rec.display_name = f"{rec.first_name or ''} {rec.last_name or ''}".strip()
```

### Compute con store condicional
```python
@api.depends("state")
def _compute_is_editable(self):
    for rec in self:
        rec.is_editable = rec.state == "draft"
```

### Inverse (campo writable computado)
```python
@api.depends("price_total", "quantity")
def _compute_price_unit(self):
    for rec in self:
        rec.price_unit = rec.price_total / rec.quantity if rec.quantity else 0.0

def _inverse_price_unit(self):
    for rec in self:
        rec.price_total = rec.price_unit * rec.quantity
```

---

## `@api.onchange`

```python
@api.onchange("partner_id")
def _onchange_partner_id(self):
    if self.partner_id:
        self.pricelist_id = self.partner_id.property_product_pricelist
        self.payment_term_id = self.partner_id.property_payment_term_id
```

> **Importante**: onchange NO se ejecuta al modificar desde codigo Python. Solo responde a cambios en la UI.

---

## CRUD (Create, Read, Update, Delete)

### `create()` con campos adicionales
```python
@api.model_create_multi
def create(self, vals_list):
    for vals in vals_list:
        if not vals.get("name"):
            vals["name"] = self.env["ir.sequence"].next_by_code("my.model")
    return super().create(vals_list)
```

### `write()` con validaciones
```python
def write(self, vals):
    if "state" in vals and vals["state"] == "done":
        for rec in self:
            if not rec.line_ids:
                raise UserError(_("Cannot confirm without lines."))
    return super().write(vals)
```

### `unlink()` con restricciones
```python
def unlink(self):
    for rec in self:
        if rec.state != "draft":
            raise UserError(_("Only draft records can be deleted."))
    return super().unlink()
```

### `copy()` con valores por defecto
```python
def copy(self, default=None):
    default = dict(default or {})
    default.setdefault("name", _("%s (copy)") % (self.name or ""))
    default.setdefault("state", "draft")
    return super().copy(default)
```

---

## Busqueda eficiente (prevencion de N+1)

### `read_group` — para agrupaciones y totales
```python
groups = self.env["account.move.line"].read_group(
    domain=[("move_id.state", "=", "posted")],
    fields=["account_id", "balance:sum"],
    groupby=["account_id"],
)
```

### `search_read` — para busqueda con campos especificos
```python
partners = self.env["res.partner"].search_read(
    domain=[("is_company", "=", True)],
    fields=["name", "email", "phone"],
    limit=100,
)
```

### `mapped` — para extraer valores de un campo
```python
partner_ids = moves.mapped("partner_id")  # recordset
emails = partners.mapped("email")  # lista de strings
```

### `filtered` — para filtrar records en memoria
```python
posted_moves = moves.filtered(lambda m: m.state == "posted")
```

### Evitar N+1 en loops
```python
# MAL — N+1 queries
for line in lines:
    partner = line.move_id.partner_id  # cada acceso puede disparar un query

# BIEN — precargar o usar read
moves = lines.move_id  # un solo query
partners = moves.partner_id  # un solo query
```

---

## `@api.model` y `@api.model_create_multi`

```python
@api.model
def _default_sequence(self):
    return self.env["ir.sequence"].next_by_code("my.model")

@api.model_create_multi
def create(self, vals_list):
    for vals in vals_list:
        vals.setdefault("sequence", self._default_sequence())
    return super().create(vals_list)
```

---

## `sudo()` — cuando usarlo

```python
# Justificado: crear registros de configuracion para otras companias
def _create_default_journals(self):
    self.sudo().env["account.journal"].create({...})

# NO justificado: saltarse reglas de negocio del modelo actual
# Usar sudo() solo cuando sea necesario por permisos entre companias o modulos
```

---

## Campos con `default=` — patron correcto

```python
# Funcion lambda
user_id = fields.Many2one("res.users", default=lambda self: self.env.user)

# Funcion con nombre
def _default_currency(self):
    return self.env.company.currency_id

currency_id = fields.Many2one("res.currency", default=_default_currency)

# No usar default=1/0 para Boolean, usar True/False
is_active = fields.Boolean(default=True)  # correcto
# is_active = fields.Boolean(default=1)    # incorrecto
```

---

## `_description` obligatorio

```python
class MyModel(models.Model):
    _name = "my.model"
    _description = "My Model"  # obligatorio en v19
```

---

## Transacciones y contexto

```python
# NUNCA llamar cr.commit(): el framework hace commit por llamada RPC.
# Para aislar una operacion riesgosa, usar savepoint (no commit):
try:
    with self.env.cr.savepoint():
        risky_operation()
except SomeError:
    handle_error()

# ensure_one() al inicio de todo metodo de accion sobre un unico registro
def action_confirm(self):
    self.ensure_one()
    ...

# Propagar contexto. Prefijar las claves propias con el modulo para aislar su impacto.
records.with_context(mymod_skip_validation=True).action_confirm()
# Cuidado con default_<campo>: setea el default en TODO modelo con ese campo en la cadena.
```

---

## Estilo y naming

El **canon completo** (orden de definición del modelo, tabla de naming de métodos/campos, naming de
variables, formato de traducciones `_()`, orden de imports, buenas prácticas de legibilidad) está en
`AGENTS.md` → secciones "Estilo de código Python" y "Arquitectura y prácticas". Resumen rápido:

- Orden en el modelo: atributos → defaults → campos → compute/inverse/search → selection →
  constrains/onchange → CRUD → actions → métodos de negocio.
- Naming: `_compute_<campo>`, `_search_<campo>`, `_default_<campo>`, `_selection_<campo>`,
  `_check_<nombre>`, `_onchange_<campo>`, `action_<nombre>`, privados `_<nombre>`.
- Variables: `Partner = self.env['res.partner']` (CamelCase modelo); `partner_id` = **int**, no el record.
- Colecciones son booleanas (`if records:`); preferir `filtered`/`mapped`/comprehensions.
