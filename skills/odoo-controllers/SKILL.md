---
name: odoo-controllers
description: Patrones de controllers HTTP y portal web en Odoo. Rutas @http.route, herencia de controllers, sesion y contexto, portal del cliente, paginacion y seguridad. Cargar al crear endpoints web o extender el portal.
---

# Controllers HTTP y Portal — Odoo

Los controllers exponen rutas web/JSON. Viven en `controllers/<module_name>.py` (el viejo
`main.py` está **deprecado**). Para heredar un controller de otro módulo, el archivo se llama como
el módulo heredado (ej. `portal.py` para extender el portal).

## Estructura y archivo

```
module_name/
    controllers/
        __init__.py            # from . import <module_name>
        <module_name>.py       # controllers propios
        portal.py              # herencia del portal (si aplica)
```

## Ruta básica (`@http.route`)

```python
# -*- coding: utf-8 -*-
from odoo import http
from odoo.http import request


class MyModuleController(http.Controller):

    # type="http": devuelve HTML/redirect/archivo. auth: "public" | "user" | "none".
    @http.route("/my/page", type="http", auth="user", website=True)
    def my_page(self, **kw):
        records = request.env["my.model"].search([])
        return request.render("my_module.my_page_template", {"records": records})

    # type="json": para llamadas RPC desde JS/OWL. Recibe/devuelve dicts (JSON).
    @http.route("/my/data", type="json", auth="user", methods=["POST"])
    def my_data(self, **kw):
        return {"items": request.env["my.model"].search_read([], ["name"])}
```

> **`auth`**: `"user"` exige login; `"public"` permite anónimo (pero `request.env.user` es el
> usuario público — usá `sudo()` con criterio para leer datos no expuestos); `"none"` ni siquiera
> abre cursor de DB. **`csrf`**: las rutas `type="http"` con `methods=["POST"]` requieren token CSRF;
> si es un webhook externo legítimo, `csrf=False` **con comentario** que justifique por qué es seguro.

## Contexto y entorno

- `request.env` es el entorno del usuario de la request (respeta ACLs y record rules).
- Propagá contexto con `request.env["model"].with_context(key=value)` (prefijá las claves propias
  con el nombre del módulo, ej. `mymod_portal=True`).
- Evitá `sudo()` salvo necesidad clara; si lo usás, limitá el recordset y dejá comentario.

## Portal del cliente (`/my`)

Para agregar páginas al portal, heredá `portal.py` del módulo `portal`:

```python
# -*- coding: utf-8 -*-
from odoo import http
from odoo.http import request
from odoo.addons.portal.controllers.portal import CustomerPortal, pager as portal_pager


class CustomerPortalInherit(CustomerPortal):

    # Sumar el contador de mis registros a la home del portal (/my)
    def _prepare_home_portal_values(self, counters):
        values = super()._prepare_home_portal_values(counters)
        if "my_count" in counters:
            values["my_count"] = request.env["my.model"].search_count(
                self._my_records_domain()
            )
        return values

    def _my_records_domain(self):
        # El partner solo ve lo suyo: nunca exponer registros de otros.
        partner = request.env.user.partner_id
        return [("partner_id", "child_of", partner.commercial_partner_id.id)]

    @http.route(["/my/records", "/my/records/page/<int:page>"], type="http",
                auth="user", website=True)
    def portal_my_records(self, page=1, **kw):
        Model = request.env["my.model"]
        domain = self._my_records_domain()
        total = Model.search_count(domain)
        pager = portal_pager(url="/my/records", total=total, page=page, step=20)
        records = Model.search(domain, limit=20, offset=pager["offset"])
        values = self._prepare_portal_layout_values()
        values.update({"records": records, "pager": pager, "page_name": "my_records"})
        return request.render("my_module.portal_my_records", values)
```

> **Seguridad del portal (crítico)**: el `domain` SIEMPRE filtra por el partner logueado
> (`child_of` su `commercial_partner_id`). Para vistas de detalle (`/my/record/<int:rec_id>`),
> validá acceso con un helper tipo `_document_check_access("my.model", rec_id)` antes de renderizar,
> y devolvé `request.redirect("/my")` si no tiene acceso. Nunca confíes en el ID de la URL.

## Templates QWeb del portal

```xml
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <template id="portal_my_records" name="My Records">
        <t t-call="portal.portal_layout">
            <t t-set="breadcrumbs_searchbar" t-value="True"/>
            <ol class="o_portal_submenu breadcrumb">
                <li class="breadcrumb-item"><a href="/my">Home</a></li>
                <li class="breadcrumb-item active">Records</li>
            </ol>
            <t t-foreach="records" t-as="rec">
                <span t-field="rec.name"/>
            </t>
            <div t-if="pager">
                <t t-call="portal.pager"/>
            </div>
        </t>
    </template>
</odoo>
<!-- vim:expandtab:smartindent:tabstop=4:softtabstop=4:shiftwidth=4-->
```

## Buenas prácticas

- Un solo archivo de controllers por módulo (`<module_name>.py`); herencias en su archivo (`portal.py`).
- No poner lógica de negocio en el controller: delegá a métodos del modelo (`_*` / `action_*`).
- Devolvé `request.not_found()` / `request.redirect()` ante recursos inexistentes o sin acceso.
- Los assets JS/CSS del frontend se declaran en el manifest (`web.assets_frontend`), no se linkean
  externos (copialos al repo). Para componentes OWL/JS, ver el bundle del manifest.

> 🔗 Para devolver datos a componentes JS, usá rutas `type="json"`. Para integraciones con APIs
> externas (llamadas salientes), ver skill `odoo-api-integration`.
