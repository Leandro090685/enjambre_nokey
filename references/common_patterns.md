# Common Migration Patterns

Patterns and strategies that apply to any Odoo version migration.

> **Placeholders**: `<WORKSPACE_ROOT_{TARGET}>` = el workspace root de la versión destino de la
> migración (resolvelo desde `workspace.md`; no es un path fijo). `<ADDONS_ROOT_{TARGET}>` = la raíz
> de addons custom de esa versión (de `workspace.md`). `{module_path}`, `{dependency}`, `{module}`
> los completás según el módulo en juego.

## Module Analysis Strategy

Before touching any code, understand the module's surface area:

```bash
# Count Python and XML files
find {module_path} -name "*.py" -o -name "*.xml" | wc -l

# List all model definitions
grep -rn "_name\s*=" {module_path}/models/
grep -rn "_inherit\s*=" {module_path}/models/

# List all controller routes
grep -rn "@http.route" {module_path}/controllers/

# List all view definitions
grep -rn '<record.*model="ir.ui.view"' {module_path}/views/

# List all action definitions
grep -rn 'ir.actions.act_window' {module_path}/views/

# Check security files
cat {module_path}/security/ir.model.access.csv
grep -rn '<record.*model="ir.rule"' {module_path}/security/
```

## Migrating create() Overrides

This is the most common breaking pattern across versions. The signature evolved:

**Odoo 12-15**: `def create(self, vals)` with `@api.model`
**Odoo 16**: Same, but `@api.model_create_multi` encouraged
**Odoo 17-18**: `@api.model_create_multi` strongly recommended
**Odoo 19**: `create()` ALWAYS receives a list — `@api.model_create_multi` required

### Migration pattern:

```python
# BEFORE (any version ≤ 18)
@api.model
def create(self, vals):
    if not vals.get('name'):
        vals['name'] = self.env['ir.sequence'].next_by_code('my.model')
    return super().create(vals)

# AFTER (19.0+, also backward compatible with 16+)
@api.model_create_multi
def create(self, vals_list):
    for vals in vals_list:
        if not vals.get('name'):
            vals['name'] = self.env['ir.sequence'].next_by_code('my.model')
    return super().create(vals_list)
```

### Detection:
```bash
grep -rn "def create(self, vals)" {module_path} --include="*.py"
```

## Migrating write() Overrides

`write()` signature has remained stable across versions, but watch for:

- Deprecated API calls inside the body
- Changed field names in `vals` dict
- Removed context keys

```python
# Structure hasn't changed, but verify body contents
def write(self, vals):
    # Check for renamed fields, deprecated methods, etc.
    return super().write(vals)
```

## Migrating View Inheritance (xpath)

View inheritance through `xpath` is generally stable, but the target elements may have changed
in the parent view between versions. Common issues:

1. **The parent element moved or was renamed** — the xpath no longer matches
2. **The parent view was refactored** — the structure changed
3. **A field was renamed** — `xpath expr="//field[@name='old_name']"` breaks

### Strategy:
- Read the target view in the new version's source to verify xpath still matches
- Check `<WORKSPACE_ROOT_{TARGET}>/odoo/addons/{module}/views/` or `<WORKSPACE_ROOT_{TARGET}>/enterprise/{module}/views/`
- Adjust xpath expressions to match the new structure

```xml
<!-- If the parent field was renamed -->
<!-- BEFORE -->
<xpath expr="//field[@name='product_uom']" position="after">

<!-- AFTER (if field renamed in 19.0) -->
<xpath expr="//field[@name='product_uom_id']" position="after">
```

## Migrating Controllers

Controller changes across versions:

```python
# Check for these patterns:
# 1. type='json' — deprecated in 19.0 for non-JSONRPC endpoints
# 2. Route parameter names — **kw vs **routing
# 3. Request API — request.httprequest vs request.get_json_data()
# 4. csrf handling — csrf=False needed for webhook endpoints
```

### Detection:
```bash
grep -rn "@http.route" {module_path} --include="*.py"
grep -rn "type='json'" {module_path} --include="*.py"
grep -rn "type=\"json\"" {module_path} --include="*.py"
```

## Migrating Wizards (TransientModel)

Wizards generally need the same changes as regular models, plus:

- Verify the target model/view they act upon still exists
- Check `action_` method signatures
- Verify `context` keys they depend on

## Checking Module Dependencies

Before migrating, verify every dependency exists in the target version:

```bash
# Extract depends from manifest
grep -A 20 "'depends'" {module_path}/__manifest__.py

# Check each dependency exists
# Community modules:
ls <WORKSPACE_ROOT_{TARGET}>/odoo/addons/{dependency}/
# Enterprise modules:
ls <WORKSPACE_ROOT_{TARGET}>/enterprise/{dependency}/
# Extra addons:
find <ADDONS_ROOT_{TARGET}>/ -maxdepth 3 -name "__manifest__.py" -path "*/{dependency}/*"
```

### Common module renames/merges across versions:
- `sale_subscription` → merged into `sale` (v16+)
- `account.invoice` model → `account.move` (v14+, but residual references persist)
- `website_sale_stock` → functionality merged into `website_sale` (varies by version)

## Manifest Version Convention

BLUEORANGE uses two conventions depending on the Odoo version:

- **Odoo 14.0 and older**: `{odoo_version}.1.0.0` (e.g., `14.0.1.0.0`)
- **Odoo 15.0+**: `1.0.0` (simple semantic versioning)

When migrating, reset the version to `1.0.0` for the target version (unless the team
has a different convention for the specific project).

## Order of File Migration

Process files in this order to minimize cascading issues:

1. `__manifest__.py` — update version and verify depends
2. `__init__.py` (all levels) — verify imports match files
3. `models/*.py` — core logic, most breaking changes live here
4. `wizards/*.py` — similar to models but simpler
5. `controllers/*.py` — routing and HTTP changes
6. `security/ir.model.access.csv` — model names may have changed
7. `security/security.xml` — group/rule structure changes
8. `views/*.xml` — view tag and attribute changes
9. `data/*.xml` — data records, sequence definitions
10. `reports/*.xml` — report templates
11. `tests/*.py` — adapt to same API changes as models

## Dependency Module Field Renames (CRITICAL)

When a module depends on custom modules (not Odoo core), those dependencies may also rename
fields or change APIs between versions. **This is the #1 source of runtime errors missed
during static analysis** because the breaking change lives in the dependency, not the module
being migrated.

### Strategy

For each dependency in `__manifest__.py`:

1. Check if the dependency has a `migrations/` folder in the target version
2. Look for `pre-migrate.py` scripts — these often contain `ALTER TABLE RENAME COLUMN` that
   reveal field renames
3. Read the dependency's models in the target version and compare field names

```bash
# Check for migration scripts in dependencies
find <ADDONS_ROOT_{TARGET}>/ -path "*/{dependency}/migrations/*" -name "*.py"

# Look for column renames in migration scripts
grep -rn "RENAME COLUMN\|rename.*column" <ADDONS_ROOT_{TARGET}>/*/{dependency}/migrations/
```

### Real-world example: `invoice_currency_rate` module

```python
# v17/v18: field is called `currency_rate` on account.move
# v19: field renamed to `inverse_invoice_currency_rate`
# The migration script: ALTER TABLE account_move RENAME COLUMN currency_rate TO inverse_invoice_currency_rate
```

A Qweb template using `doc.currency_rate` will pass static analysis and module installation,
but will crash at **runtime** when the report is actually rendered.

### Key principle

**Module installation succeeding does NOT mean the migration is complete.** Qweb templates
evaluate field access at render time, not at install time. Always test report rendering
against real data after migration.

## Qweb Report Templates — Extra Attention Required

Report templates (Qweb) are a common source of post-migration runtime errors because:

1. **Field access is evaluated at render time**, not at module load — broken references
   won't show up during `make update`
2. **JSON/dict field structures** (like `tax_totals`) can change internal keys between
   versions without any ORM-level deprecation warning
3. **CSS/Bootstrap behavior** changes between versions affect PDF layout even with identical
   HTML markup

### Migration checklist for reports

- [ ] Check all `t-field`, `t-esc`, `t-out` references against the target version's model
- [ ] Check dict key access patterns (e.g., `doc.tax_totals['key']`) against the target
  version's compute method to verify keys still exist
- [ ] Compare CSS class usage (`col-auto`, `col-sm-*`, etc.) against the official
  invoice/report templates in the target version
- [ ] **Test by actually printing the report** against a real posted record

### Detection:
```bash
# Find all field references in Qweb templates
grep -rn 't-field=\|t-esc=\|t-out=' {module_path}/report/ --include="*.xml"

# Find dict key access patterns
grep -rn "\['" {module_path}/report/ --include="*.xml"
```

## Post-Migration Verification

After all changes are applied:

```bash
# Syntax check all Python files
find {module_path} -name "*.py" -exec python3 -m py_compile {} \;

# Check XML well-formedness
find {module_path} -name "*.xml" -exec xmllint --noout {} \;

# Search for leftover deprecated patterns (version-specific)
# These come from the version reference files
```
