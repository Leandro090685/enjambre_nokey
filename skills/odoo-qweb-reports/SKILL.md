---
name: odoo-qweb-reports
description: Patrones de reportes QWeb en Odoo. Templates QWeb, generacion de PDF, variables de contexto, estilos, y buenas practicas para reportes imprimibles.
---

# Patrones de Reportes QWeb — Odoo

## Estructura basica de un reporte

### 1. Definir el reporte en `__manifest__.py`

```python
"data": [
    "report/my_report_templates.xml",
    "report/my_report_action.xml",
],
```

### 2. Accion del reporte (`report/my_report_action.xml`)

```xml
<record id="my_model_action_report" model="ir.actions.report">
    <field name="name">My Model Report</field>
    <field name="model">my.model</field>
    <field name="report_type">qweb-pdf</field>
    <field name="report_name">my_module.template_my_report</field>
    <field name="report_file">my_module.template_my_report</field>
    <field name="binding_model_id" ref="model_my_model"/>
    <field name="binding_type">report</field>
</record>
```

### 3. Template QWeb (`report/my_report_templates.xml`)

```xml
<template id="template_my_report">
    <t t-call="web.html_container">
        <t t-call="web.external_layout">
            <div class="page">
                <!-- Encabezado -->
                <h2>My Report</h2>
                <p>Date: <t t-esc="o.date"/></p>

                <!-- Tabla de lineas -->
                <table class="table table-condensed">
                    <thead>
                        <tr>
                            <th>Product</th>
                            <th class="text-right">Quantity</th>
                            <th class="text-right">Price</th>
                        </tr>
                    </thead>
                    <tbody>
                        <t t-foreach="o.line_ids" t-as="line">
                            <tr>
                                <td><t t-esc="line.product_id.name"/></td>
                                <td class="text-right"><t t-esc="line.quantity"/></td>
                                <td class="text-right"><t t-esc="line.price_unit"/></td>
                            </tr>
                        </t>
                    </tbody>
                </table>
            </div>
        </t>
    </t>
</template>
```

---

## Variables disponibles en el template

| Variable | Significado |
|----------|-------------|
| `o` | El record (o records) del modelo |
| `docs` | Alias de `o` (para compatibilidad) |
| `doc` | El primer record en `docs` |
| `doc_ids` | IDs de los records seleccionados |
| `doc_model` | Nombre tecnico del modelo |
| `user` | Usuario actual (`res.users`) |
| `res_company` | Compania del usuario |
| `time` | Modulo `time` de Python |
| `context` | Diccionario de contexto |

---

## Renderizar reporte desde Python

```python
def action_print_report(self):
    return self.env["ir.actions.report"]._render_qweb_pdf(
        "my_module.template_my_report",
        self.ids,
    )
```

### Retornar PDF como accion
```python
def action_print(self):
    report_action = self.env.ref("my_module.my_model_action_report")
    return report_action.report_action(self)
```

---

## Directivas QWeb principales

### `t-esc` — mostrar valor escapado (seguro)
```xml
<p><t t-esc="o.name"/></p>
```

### `t-out` — mostrar valor (similar a t-esc, v17+)
```xml
<p><t t-out="o.name"/></p>
```

### `t-raw` — mostrar HTML sin escapar (peligroso)
```xml
<div><t t-raw="o.html_content"/></div>
```

### `t-foreach` / `t-as` — iterar
```xml
<t t-foreach="o.line_ids" t-as="line">
    <p><t t-esc="line.name"/></p>
</t>
```

### `t-if` / `t-else` — condicional
```xml
<t t-if="o.state == 'done'">
    <p>Completed</p>
</t>
<t t-else="">
    <p>Pending</p>
</t>
```

### `t-set` / `t-value` — variables
```xml
<t t-set="total" t-value="sum(o.line_ids.mapped('price_subtotal'))"/>
<p>Total: <t t-esc="total"/></p>
```

### `t-call` — incluir otro template
```xml
<t t-call="my_module.other_template"/>
```

### `t-att` — atributo dinamico
```xml
<div t-att-class="'text-' + ('danger' if o.state == 'error' else 'muted')">
    <t t-esc="o.state"/>
</div>
```

---

## Estilos comunes en reportes

```xml
<!-- Tabla con estilo Bootstrap -->
<table class="table table-condensed table-bordered">
    ...
</table>

<!-- Texto alineado -->
<p class="text-right"><t t-esc="amount"/></p>
<p class="text-center">Centered text</p>

<!-- Filas con color condicional -->
<tr t-att-class="'bg-danger' if line.quantity < 0 else ''">
    ...
</tr>

<!-- Saltos de pagina -->
<p style="page-break-after: always;"/>

<!-- Margenes y espaciado -->
<div class="mt-2 mb-3">
```

---

## Datos extra en el contexto

```python
def action_print_report(self):
    return self.env["ir.actions.report"]._render_qweb_pdf(
        "my_module.template_my_report",
        self.ids,
        data={
            "extra_param": "value",
            "include_logo": True,
        },
    )
```

En el template:
```xml
<t t-foreach="data.get('extra_param', '')" .../>
```

---

## Checklist de reportes

- [ ] El template usa `t-call="web.html_container"` y `t-call="web.external_layout"`
- [ ] Los campos accedidos existen en el modelo (verificar con `fields_get`)
- [ ] Los campos Many2one se acceden con `.field_id` (no solo `.field`)
- [ ] Las tablas usan clases Bootstrap (`table table-condensed`)
- [ ] `t-esc` para datos de usuario (no `t-raw` salvo HTML confiable)
- [ ] La accion del reporte tiene `binding_model_id` para aparecer en el boton Print
