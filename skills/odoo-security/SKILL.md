---
name: odoo-security
description: Patrones de seguridad para Odoo. ACLs (ir.model.access.csv), record rules (ir.rule), grupos, usuarios. Cambios por version. Cargar al configurar ACLs, grupos o record rules.
---

# Patrones de Seguridad — Odoo

> **Versión y breaking changes**: la versión objetivo está en `.claude/workspace.md` (`ODOO_VERSION`).
> Los patrones de grupos/usuarios cambian por versión (en v19: `privilege_id`, `group_ids`,
> `has_group()`). Verificá `references/v{ODOO_VERSION}_gotchas.md` (secciones `res.groups`/`res.users`).

## `ir.model.access.csv` (obligatorio)

Todo modelo nuevo (incluyendo `TransientModel`) debe tener su entrada ACL:

```csv
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_my_model_user,my.model.user,model_my_model,base.group_user,1,1,1,0
access_my_model_manager,my.model.manager,model_my_model,my_module.group_manager,1,1,1,1
```

### Formato de acceso segun rol

| Rol | perm_read | perm_write | perm_create | perm_unlink |
|-----|-----------|------------|-------------|-------------|
| Usuario base | 1 | 1 | 1 | 0 |
| Manager/Admin | 1 | 1 | 1 | 1 |
| Solo lectura | 1 | 0 | 0 | 0 |

> **No olvidar**: los TransientModel necesitan `ir.model.access.csv` explicito en v19.

---

## Grupos de seguridad — `privilege_id` (NUEVO en v19)

### `category_id` fue ELIMINADO
En versiones anteriores:
```xml
<!-- INCORRECTO en v19 -->
<record id="group_manager" model="res.groups">
    <field name="name">Manager</field>
    <field name="category_id" ref="base.module_category_hidden"/>
</record>
```

### Nuevo patron con `privilege_id`
```xml
<!-- 1. Crear el privilegio -->
<record id="privilege_my_module" model="res.groups.privilege">
    <field name="name">My Module Privilege</field>
</record>

<!-- 2. Crear el grupo vinculado al privilegio -->
<record id="group_manager" model="res.groups">
    <field name="name">Manager</field>
    <field name="privilege_id" ref="privilege_my_module"/>
    <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
</record>
```

### Grupo basico (herencia de implied)
```xml
<record id="group_user" model="res.groups">
    <field name="name">User</field>
    <field name="privilege_id" ref="privilege_my_module"/>
    <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
</record>
```

---

## `res.users` — `group_ids` (NO `groups_id`)

### Verificar pertenencia a grupo (en Python)
```python
# CORRECTO (v19)
if self.env.user.has_group("my_module.group_manager"):
    # logica para managers

# INCORRECTO (deprecado en v19)
# if self.user_has_groups("my_module.group_manager"):
```

### Asignar grupos a usuario
```python
# CORRECTO (v19)
user.write({"group_ids": [(4, group_id)]})

# INCORRECTO (viejo)
# user.write({"groups_id": [(4, group_id)]})
```

### Domain para filtrar usuarios por grupo
```xml
<!-- Usar all_group_ids para implied groups -->
<field name="user_id" domain="[('all_group_ids', 'in', [ref('my_module.group_manager')])]"/>
```

---

## Record Rules (`ir.rule`)

### Record rule multi-compania
```xml
<record id="rule_my_model_company" model="ir.rule">
    <field name="name">My Model: multi-company</field>
    <field name="model_id" ref="model_my_model"/>
    <field name="domain_force">[('company_id', 'in', company_ids + [False])]</field>
    <field name="groups" eval="[(4, ref('base.group_user'))]"/>
</record>
```

### Record rule por estado
```xml
<record id="rule_my_model_draft_only" model="ir.rule">
    <field name="name">My Model: solo draft para usuarios</field>
    <field name="model_id" ref="model_my_model"/>
    <field name="domain_force">[('state', '=', 'draft')]</field>
    <field name="groups" eval="[(4, ref('base.group_user'))]"/>
    <field name="perm_read" eval="True"/>
    <field name="perm_write" eval="True"/>
    <field name="perm_create" eval="False"/>
    <field name="perm_unlink" eval="False"/>
</record>
```

### Record rule con global (sin grupos — aplica a todos)
```xml
<record id="rule_my_model_global" model="ir.rule">
    <field name="name">My Model: global rule</field>
    <field name="model_id" ref="model_my_model"/>
    <field name="domain_force">[('is_active', '=', True)]</field>
    <!-- sin campo groups = aplica a todos -->
</record>
```

---

## Campo `company_id` — patron estandar

```python
company_id = fields.Many2one(
    "res.company",
    string="Company",
    default=lambda self: self.env.company,
    required=True,
)
```

> Siempre agregar `company_id` a modelos que representan datos de negocio. Usar `default=lambda self: self.env.company`.

---

## `_check_company` — validacion automatica

Odoo verifica automaticamente que los records relacionados pertenezcan a la misma compania si el campo Many2one tiene `check_company=True`:

```python
partner_id = fields.Many2one("res.partner", string="Partner", check_company=True)
```

Esto evita tener que escribir `@api.constrains` manuales para validar `company_id` entre registros relacionados.

---

## Seguridad en metodos con `sudo()`

```python
# Justificado: acceder a datos de configuracion multi-compania
def _get_default_account(self):
    return self.sudo().env["account.account"].search([
        ("company_id", "=", self.env.company.id),
        ("account_type", "=", "asset_receivable"),
    ], limit=1)

# NO justificado: saltarse validaciones de negocio
# Un metodo de negocio NUNCA debe usar sudo() sobre si mismo
```

---

## Checklist rapido de seguridad

- [ ] `ir.model.access.csv` tiene entradas para todos los modelos nuevos
- [ ] `TransientModel` tiene ACL explicita
- [ ] Grupos usan `privilege_id` (no `category_id`)
- [ ] `res.users` usa `group_ids` (no `groups_id`)
- [ ] `has_group()` (no `user_has_groups()`)
- [ ] Record rules multi-compania para datos de negocio
- [ ] Campo `company_id` en modelos de negocio con `default`
- [ ] `check_company=True` en Many2one relevantes
- [ ] `sudo()` solo cuando es justificado y documentado
