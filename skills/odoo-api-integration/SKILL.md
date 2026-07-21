---
name: odoo-api-integration
description: Patrones para integrar Odoo con APIs externas (REST/JSON, XML-RPC y afines). Cliente HTTP con timeouts y reintentos, manejo de errores, credenciales en config, savepoints, mapeo a modelos y testing con mocks. Cargar al consumir o exponer servicios externos.
---

# Integración con APIs externas — Odoo

Patrones para llamadas **salientes** a servicios externos genéricos (pasarelas de pago, ERPs de
terceros, otras instancias Odoo, cualquier servicio REST/JSON o XML-RPC). Este skill es el **cómo**
técnico de la integración, agnóstico del negocio.

## Cliente HTTP (timeouts SIEMPRE)

```python
# -*- coding: utf-8 -*-
import logging

import requests

from odoo import _, models
from odoo.exceptions import UserError

_logger = logging.getLogger(__name__)

DEFAULT_TIMEOUT = 30  # segundos — NUNCA llamar sin timeout (cuelga el worker)


class MyIntegration(models.AbstractModel):
    _name = "my.integration"
    _description = "External API Client"

    def _api_base_url(self):
        # Endpoint configurable, no hardcodeado. Ver "Credenciales y config".
        return self.env["ir.config_parameter"].sudo().get_param("my_integration.base_url")

    def _api_post(self, path, payload):
        url = "%s/%s" % (self._api_base_url().rstrip("/"), path.lstrip("/"))
        try:
            resp = requests.post(url, json=payload, timeout=DEFAULT_TIMEOUT,
                                 headers=self._api_headers())
            resp.raise_for_status()
        except requests.Timeout:
            raise UserError(_("The external service timed out. Try again later."))
        except requests.HTTPError as e:
            _logger.warning("API %s -> %s: %s", url, resp.status_code, resp.text[:500])
            raise UserError(_("External service error (%(code)s).", code=resp.status_code))
        except requests.RequestException as e:
            _logger.exception("API call failed: %s", url)
            raise UserError(_("Could not reach the external service."))
        return resp.json()
```

> **Errores → `UserError` traducible**: traducí el mensaje al usuario con `_()`, pero logueá el
> detalle técnico (status, body) con `_logger` — sin filtrar credenciales. No dejes que un
> `requests.RequestException` escale crudo a la UI.

## Reintentos con backoff (idempotente)

Reintentá solo operaciones **idempotentes** (GET, consultas de estado). Para POST que crean algo
(ej. crear un pedido/registro en el sistema externo), no reintentes a ciegas: consultá estado primero
o usá un identificador único.

```python
import time

def _api_get_with_retry(self, path, retries=3):
    for attempt in range(retries):
        try:
            return self._api_get(path)
        except UserError:
            if attempt == retries - 1:
                raise
            time.sleep(2 ** attempt)  # 1s, 2s, 4s
```

## Credenciales y configuración

- **Nunca hardcodear** URLs, tokens ni claves. Guardarlas en:
  - `ir.config_parameter` (global, vía `.sudo().get_param`/`set_param`) para endpoints/flags.
  - Campos en `res.company` para credenciales por compañía (multi-company).
- No commitear secrets. Documentá los parámetros esperados en el README del módulo.

## Cliente XML-RPC (otra instancia Odoo u otro sistema que lo exponga)

Para integrar contra **otra instancia Odoo** (u otro sistema que expone XML-RPC), el patrón de auth +
llamada es siempre el mismo: autenticar una vez, reusar el `uid`, y envolver la llamada con el mismo
manejo de errores/timeout que el cliente HTTP.

```python
import xmlrpc.client

url = self.env["ir.config_parameter"].sudo().get_param("my_integration.remote_url")
db = self.env["ir.config_parameter"].sudo().get_param("my_integration.remote_db")
username, password = self._get_remote_credentials()  # nunca hardcodeadas

common = xmlrpc.client.ServerProxy("%s/xmlrpc/2/common" % url)
uid = common.authenticate(db, username, password, {})
if not uid:
    raise UserError(_("Could not authenticate against the external Odoo instance."))

models_proxy = xmlrpc.client.ServerProxy("%s/xmlrpc/2/object" % url)
result = models_proxy.execute_kw(
    db, uid, password, "res.partner", "search_read",
    [[["email", "=", partner_email]]], {"fields": ["id", "name"]},
)
```

> Mismas reglas que el cliente HTTP: credenciales fuera del código (`ir.config_parameter` o campos de
> `res.company`), sin `cr.commit()`, y loguear el detalle técnico sin exponerlo crudo al usuario.

## Aislar el efecto en la transacción (savepoints, NO commit)

`cr.commit()` está **prohibido** (AGENTS.md): el framework hace commit por llamada RPC. Para que un
fallo en una llamada externa no aborte toda la transacción, aislá con un savepoint:

```python
try:
    with self.env.cr.savepoint():
        response = self._api_post("emit", payload)
        record.write({"external_id": response["id"], "state": "sent"})
except UserError:
    # El savepoint revierte solo lo de adentro; registramos el fallo sin romper el resto.
    record.write({"state": "error"})
```

## Mapeo de respuesta a modelos

- Validá la forma de la respuesta antes de escribir (no asumas claves: usá `.get()`).
- Convertí tipos explícitamente (fechas con `fields.Date.to_date`, montos a `float`).
- Persistí el identificador externo (`external_id`) para idempotencia y conciliación posterior.

## Testing (mockear la red, nunca llamar de verdad)

```python
from unittest.mock import patch
from odoo.tests import TransactionCase, tagged


@tagged("post_install", "-at_install")
class TestMyIntegration(TransactionCase):

    def test_emit_ok(self):
        fake = {"id": "EXT-123", "status": "ok"}
        with patch.object(type(self.env["my.integration"]), "_api_post", return_value=fake):
            rec = self.env["my.model"].create({"name": "X"})
            rec.action_emit()
            self.assertEqual(rec.external_id, "EXT-123")
```

> 🔗 Para escribir la suite completa de tests, ver skill `odoo-tests`. Para **recibir** llamadas
> entrantes (webhooks), ver skill `odoo-controllers` (rutas `type="json"` con `csrf=False` justificado).
