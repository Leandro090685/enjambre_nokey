---
name: odoo-tests
description: Patrones para escribir tests en Odoo, backend y e2e. Clases @tagged, eleccion de base (TransactionCase/SingleTransactionCase/HttpCase), datos en setUpClass, asserts, Form para onchanges, mocking, Tours e2e de UI (HttpCase.start_tour + web_tour), y alcance bajo politica de repo (flujos troncales). Cargar si el usuario pide tests o si el repo los requiere (.swarm.conf TESTS=required / E2E=required).
---

# Tests — Odoo

> ⚠️ **Convención del proyecto (AGENTS.md)**: **NO escribir tests salvo que se pidan explícitamente o que
> el repo los requiera** (archivo `.swarm.conf` con `TESTS=required` para backend y/o `E2E=required`
> para e2e de UI — ver "Alcance bajo política de repo" abajo). Para **ejecutar** tests en Docker, ver
> skill `debugging-odoo` (este enseña a **escribirlos**).

## Estructura

```
module_name/
    tests/
        __init__.py          # from . import test_my_model
        test_my_model.py
```

`tests/` no se declara en `data` del manifest: Odoo descubre los tests por convención. El
`__init__.py` del módulo **no** importa `tests/`.

## Clase base — cuál heredar

| Base | Cuándo | Aislamiento |
|------|--------|-------------|
| `TransactionCase` | Caso por defecto. Cada test corre en su savepoint y se revierte. | Por test (rollback) |
| `SingleTransactionCase` | Suite donde los tests comparten estado acumulado (raro). | Compartido |
| `HttpCase` | Flujos HTTP, controllers, tours JS (`self.start_tour`). | Por test + servidor |

## Test típico (`TransactionCase`)

```python
# -*- coding: utf-8 -*-
from odoo.tests import TransactionCase, tagged
from odoo.exceptions import ValidationError


# at_install corre al instalar; post_install tras instalar TODOS los modulos (recomendado
# para no romper por orden de instalacion). Se excluyen con: --test-tags '-at_install'.
@tagged("post_install", "-at_install")
class TestMyModel(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        # Datos compartidos por los tests de la clase (se crean una vez).
        cls.partner = cls.env["res.partner"].create({"name": "Test Partner"})
        cls.record = cls.env["my.model"].create({
            "name": "Base",
            "partner_id": cls.partner.id,
        })

    def test_compute_total(self):
        # Arrange / Act / Assert
        self.record.write({"qty": 3, "price": 10})
        self.assertEqual(self.record.amount_total, 30.0)

    def test_constraint_name_required(self):
        with self.assertRaises(ValidationError):
            self.env["my.model"].create({"name": ""})
```

## Probar onchanges con `Form`

`Form` simula la vista: dispara onchanges y computes como lo haría la UI.

```python
from odoo.tests import Form

def test_onchange_partner(self):
    with Form(self.env["my.model"]) as f:
        f.partner_id = self.partner
        # el onchange ya corrió: el valor derivado está disponible
        self.assertEqual(f.currency_id, self.partner.property_product_pricelist.currency_id)
```

## Asserts útiles

- `self.assertEqual / assertTrue / assertFalse / assertIn`
- `with self.assertRaises(UserError):` — para validar errores esperados.
- `self.assertRecordValues(records, [{...}, {...}])` — comparar valores de un recordset.
- `with self.assertQueryCount(admin=5):` — detectar regresiones de N+1 (cuando importa performance).

## Mocking de externos

No llamar a APIs/servicios reales en los tests: mockear con `unittest.mock.patch`.

```python
from unittest.mock import patch

def test_emit_mocks_api(self):
    with patch.object(type(self.env["my.integration"]), "_api_post",
                      return_value={"id": "X1"}):
        self.record.action_emit()
        self.assertEqual(self.record.external_id, "X1")
```

## E2E — Tours de Odoo (`HttpCase.start_tour`)

Los tests **e2e de UI** en Odoo se hacen con **Tours** (no Playwright ni Selenium a mano): una
secuencia de pasos JS que maneja un **Chrome headless** real recorriendo la interfaz, disparada
desde un test Python `HttpCase`. Es el mismo mecanismo que usa el core (`website_sale`, etc.), corre
en el **mismo runner** que el backend (`--test-tags`) y arma sus fixtures por **ORM**.

Un tour son **dos piezas**:

**1) El tour JS** — bajo `static/src/**`, registrado en `web_tour.tours`:
```javascript
/** @odoo-module **/
import { registry } from "@web/core/registry";

registry.category("web_tour.tours").add("my_module_checkout_tour", {
    url: "/shop",                 // dónde arranca
    steps: () => [
        { trigger: ".oe_product:first a", run: "click" },
        { trigger: "a:contains('Add to cart')", run: "click" },
        { trigger: "a[href='/shop/cart']", run: "click" },
        { trigger: ".btn:contains('Checkout')", run: "click" },
        // último paso: un trigger que solo existe si el flujo terminó OK
        { trigger: ".oe_website_sale_confirmation" },
    ],
});
```
Declarar el asset en el manifest (bundle correcto: `web.assets_frontend` para portal/website,
`web.assets_backend` para el backoffice):
```python
"assets": {"web.assets_frontend": ["my_module/static/src/js/checkout_tour.esm.js"]},
```

**2) El test `HttpCase`** que lo dispara y valida el resultado en la DB:
```python
# -*- coding: utf-8 -*-
from odoo.tests import HttpCase, tagged

# tag propio del modulo para poder correr SOLO el e2e: --test-tags '/my_module,my_module_e2e'
@tagged("post_install", "-at_install", "my_module_e2e")
class TestCheckoutTour(HttpCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        # Fixtures por ORM (igual que backend): productos, partner, config web, etc.
        cls.product = cls.env["product.template"].create({
            "name": "Test Product", "is_published": True, "list_price": 10.0,
        })

    def test_checkout_flow(self):
        # Recorre el flujo real por la UI; login por kwarg.
        self.start_tour("/shop", "my_module_checkout_tour", login="portal")
        # Después del tour, assert de estado en la DB (que la venta quedó creada/confirmada).
        order = self.env["sale.order"].search([("partner_id.login", "=", "portal")], limit=1)
        self.assertTrue(order, "El checkout debía crear una sale.order")
```

> ⚠️ **Chrome es prerequisito — los tours deben CORRER, no saltearse.** Necesitan `chromium`/
> `google-chrome` en el contenedor (o `ODOO_BROWSER_BIN`). El flujo lo **asegura ANTES de correr**:
> `odoo_runtime.sh chrome-check`; si falta, @testing avisa y —con OK del usuario— lo instala
> (`odoo_runtime.sh chrome-install`), así el tour se ejecuta de verdad. Ojo: Odoo **saltea** el tour
> si no hay Chrome, y un e2e **skipped no cuenta como pasado** (falla del gate). Ver `debugging-odoo`.

> 🔎 **Debug de tours**: el step falla con "tour not found"/"element not found" si el trigger no
> matchea. Usá selectores estables (clases de negocio, `:contains(...)`), y como último paso un
> trigger que **solo aparece si el flujo terminó OK** (así el tour verde = flujo completo).

## Alcance bajo política de repo (`.swarm.conf` `TESTS=required` / `E2E=required`)

Cuando el repo declara la política, los tests son parte de la tarea — pero el alcance es acotado
a propósito (**sin exagerar**). Dos ejes independientes:

### Backend (`TESTS=required`)
- **Flujo troncal** = el/los caminos de negocio principales del módulo: lo que el módulo *hace*
  (ej. crear→confirmar, el compute central, la constraint que protege el dato, la acción principal
  de un wizard). Si el módulo desapareciera, es lo primero que se rompería visible.
- **Módulo sin `tests/`** → suite inicial: un `test_*.py` por área/modelo tocado, con el happy path
  de cada flujo troncal + 1-2 constraints/validaciones críticas. Nada más.
- **Módulo con tests** → solo el flujo que el cambio agrega/modifica; no ampliar ni refactorizar la
  suite existente (diff mínimo también aplica a tests).
- **Qué NO hacer**: permutaciones exhaustivas de edge cases, tests del framework de Odoo (ORM,
  vistas que renderizan, ACLs estándar), tests de getters triviales, ni suites de performance no
  pedidas. Un cambio menor (string, label, help) no exige tests.

### E2E (`E2E=required`)
- **Solo módulos con superficie de UI** (portal/website/ecommerce, JS en `static/src`, controllers)
  **y un flujo de UI troncal**. Un módulo backend puro (solo modelos + vistas backend) **no** lleva
  tour, aunque el repo declare `E2E=required`.
- **Un tour por flujo de UI troncal**, cubriendo el camino happy de punta a punta (ej. el checkout,
  el alta desde el portal, el paso clave de un asistente web). No un tour por cada botón.
- **Módulo con tour** → si el cambio toca ese flujo, ajustá el tour; si no, dejalo.
- **Qué NO hacer**: e2e de flujos que ya cubre un test backend más barato, tours de pantallas sin
  lógica, ni recorrer variantes exhaustivas de UI.

**Cerrar la tarea = correrlos** (ambos ejes): se ejecutan antes de dar por terminado
(`odoo_runtime.sh test <db> <modulo>` / `run-tests <db> '/<modulo>,<tag_e2e>'` — ver
`debugging-odoo`). Para e2e, un tour **SKIPPED** (Chrome ausente) **no** cuenta como pasado.

## Buenas prácticas

- Un archivo `test_*.py` por área/modelo; nombres descriptivos `test_<que_valida>`.
- Datos mínimos y deterministas en `setUpClass`; no depender de datos demo salvo que se testee eso.
- Tests rápidos y aislados: preferí `TransactionCase` (rollback) sobre estado compartido.
- No testees el framework de Odoo; testeá **tu** lógica (computes, constraints, acciones, flujos).

> 🔗 Para correr la suite (`--test-tags`, `-u module --test-enable` en Docker), ver `debugging-odoo`.
> Para integraciones externas, ver `odoo-api-integration`.
