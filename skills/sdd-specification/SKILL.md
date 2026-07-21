---
name: sdd-specification
description: Metodologia SDD (Specification-Driven Development) para Odoo. Define el formato de especificaciones tecnicas, cuando usarlas, y como conectarlas con la implementacion. Cargar antes de generar o implementar specs.
---

# SDD — Specification-Driven Development para Odoo

## Filosofia

**Spec-first, code-second.** Antes de escribir una linea de codigo, existe una especificacion formal que define exactamente que se va a construir, como, y con que criterios de aceptacion.

Esto elimina ambiguedades, reduce retrabajo, y permite que cualquier agente (@code-dev, @reviewer, @testing) trabaje con una fuente unica de verdad.

### Una spec por modulo, documento vivo (no acumulativo)

La spec **no es por feature: es por modulo**. Cada modulo SDD tiene **un solo** archivo de spec que
describe el modulo **tal como esta hoy** (current-state), no su historia. Cuando se agrega o cambia
una feature, la spec se **edita en sitio** —se modifica la fila/seccion afectada— en vez de apilar
un changelog. El historial lo da git; la spec siempre dice "que es el modulo *ahora*".

Consecuencias (las tres reglas que definen el modelo):

1. **Fuente de verdad al levantar contexto.** Si un modulo tiene `specs/`, la spec es la PRIMERA
   fuente de contexto (antes/junto al README). @client-context, @code-dev y @sdd-generate la leen
   antes de grepear el codigo.
2. **Version de la spec == version del modulo.** La spec espeja el campo `version` del
   `__manifest__.py`, en formato **`x.x.x` simple** (sin prefijo de serie de Odoo: `1.0.0`, nunca
   `19.0.1.0.0` — Odoo antepone la serie solo). Cada cambio sobre el modulo bumpea el manifest y la
   spec **juntos**, al mismo valor. El hook `post_write.sh` avisa (no bloquea) si hay drift.
3. **Gate de conflicto.** Si un cambio pedido **contradice** la spec (un campo/metodo/regla/alcance
   que la spec define distinto o excluye), se FRENA antes de tocar codigo, se le avisa al usuario y
   recien si confirma se **edita la spec** para reflejar la nueva decision y despues se implementa.

### Las 4 fases del ciclo SDD

Inspirado en spec-kit (`clarify → specify → analyze → implement`), adaptado al enjambre Nokey y a Odoo:

| Fase | Quien | Que produce |
|------|-------|-------------|
| **1. Clarify** | @sdd-generate (con el usuario) | Preguntas resueltas, sin huecos ni ambiguedades |
| **2. Specify** | @sdd-generate (apoyado en @researcher) | `specs/<modulo>.md` con modelos, campos, metodos, **plan del cambio** y **anclajes al core** |
| **3. Analyze** | @reviewer (modo pre-implementacion) | Veredicto de consistencia interna spec↔tareas↔core, **antes** de codear |
| **4. Implement** | @code-dev | Codigo, ejecutando el plan del cambio T01..Tnn en orden, + spec editada en sitio + version sincronizada |

## Cuando usar SDD

| Situacion | Usar SDD? |
|-----------|-----------|
| Feature nueva con 3+ modelos/metodos | ✅ Siempre |
| Modificacion compleja de modulo existente | ✅ Recomendado |
| Modificacion (incluso simple) de un modulo que **ya tiene spec** | ✅ Siempre — la spec se actualiza en sitio + version sync |
| Bug fix simple en modulo **sin** spec | ❌ No necesario |
| Agregar un campo simple a modulo **sin** spec | ❌ No necesario |
| Refactoring grande | ✅ Siempre |
| Migracion de modulo | ❌ La migracion tiene su propio proceso |

> Regla practica: **si el modulo tiene `specs/`, todo cambio pasa por la spec** (leerla como fuente
> de verdad, chequear conflicto, actualizarla en sitio, sincronizar version), por chico que sea.

## Formato de spec

La spec vive en `<modulo>/specs/<module_technical_name>.md` (**un solo archivo por modulo**) con
este formato:

```markdown
# Spec de modulo: <module_technical_name>

| Campo | Valor |
|-------|-------|
| **Modulo** | `<nombre tecnico>` |
| **Version** | `1.0.0` (== `version` del `__manifest__.py`, formato `x.x.x`) |
| **Serie Odoo** | `19` (informativa — la serie de `ODOO_VERSION`, no es la version de la spec) |
| **Estado** | `draft | clarified | approved | analyzed | implemented | verified` |
| **Actualizado** | `YYYY-MM-DD` |

## Objetivo

<Que problema resuelve el MODULO, en una o dos frases. Si el modulo cubre varias features,
describir el objetivo general.>

## Decisiones vigentes

> Decisiones de diseño que rigen HOY (no es un log de preguntas historicas). Si una decision nueva
> pisa una vieja, se **edita la fila** correspondiente — no se agrega una fila contradictoria. Lo
> que se asumio sin respuesta del usuario va marcado `[ASUNCION]` para que quede auditable.

| # | Decision | Valor vigente |
|---|----------|---------------|
| D1 | ¿El campo `total` incluye impuestos? | Si, total con impuestos incluidos |
| D2 | ¿Multi-compania? | Si, cada compania ve solo sus registros |
| D3 | ¿Que pasa al eliminar un registro confirmado? | `[ASUNCION]` Se bloquea (default conservador) |

## Alcance

### Incluye
- <item 1>
- <item 2>

### NO incluye
- <item 1>
- <item 2>

## Modelos

### Nuevos

| Modelo (_name) | _description | Hereda de |
|----------------|-------------|-----------|
| `my.model` | My Model | `models.Model` |

### Extendidos

| Modelo | _inherit | Que se agrega |
|--------|----------|--------------|
| `res.partner` | - | Campo `x_custom_field` |

## Campos

| Modelo | Campo | Tipo | String | Requerido | Default | Restricciones |
|--------|-------|------|--------|-----------|---------|--------------|
| `my.model` | `name` | Char | Name | Si | - | Unique por company |
| `my.model` | `date` | Date | Date | Si | `fields.Date.today()` | - |
| `res.partner` | `x_custom_field` | Boolean | Is Custom | No | `False` | - |

## Metodos

### `MyModel.action_confirm()`

- **Proposito**: Confirmar el registro y cambiar estado
- **Decoradores**: ninguno
- **Logica**:
  1. Validar que `date` no sea futura
  2. Validar que existan lineas (`line_ids`)
  3. Cambiar `state` a `confirmed`
- **Retorna**: `None`
- **Errores**:
  - `ValidationError` si `date > today`
  - `UserError` si no hay lineas

### `MyModel._compute_total()`

- **Proposito**: Calcular total desde lineas
- **Decoradores**: `@api.depends('line_ids.price_subtotal')`
- **Logica**: `sum(line_ids.mapped('price_subtotal'))`
- **Retorna**: `None` (campo computed)
- **Store**: `True`

## Vistas

### Form view (`my_model_view_form`)
- **Header**: botones Confirm/Cancel, statusbar
- **Sheet**: grupo con name + date, notebook con lineas
- **Chatter**: message_follower_ids, activity_ids, message_ids

### List view (`my_model_view_list`)
- **Columnas**: name, date, state (widget badge), total (sum)
- **Decoration**: `decoration-danger="state == 'cancelled'"`

### Search view (`my_model_view_search`)
- **Filtros**: name, date, state (draft/confirmed/done)
- **Group by**: state

## Seguridad

| Modelo | Grupo | read | write | create | unlink |
|--------|-------|------|-------|--------|--------|
| `my.model` | `base.group_user` | 1 | 1 | 1 | 0 |
| `my.model` | `my_module.group_manager` | 1 | 1 | 1 | 1 |

### Grupos
- `my_module.group_manager` (privilege: `my_module.privilege_my_module`, implied: `base.group_user`)

## Reglas de negocio

1. **RB01**: No se puede confirmar un registro con fecha futura
2. **RB02**: No se puede eliminar un registro confirmado
3. **RB03**: El total se recalcula automaticamente al modificar lineas

## Edge cases

- **Sin lineas**: no se puede confirmar (`UserError`)
- **Fecha nula**: no se puede guardar (`required=True`)
- **Multi-compania**: cada compania ve solo sus registros (`company_id` + record rule)
- **Lineas con cantidad 0**: permitido pero muestra warning

## Criterios de aceptacion

> Numerados (CA01, CA02…) para que el **plan del cambio** pueda referenciarlos y @reviewer
> verifique cobertura. Describen el comportamiento esperado del modulo HOY (current-state).

- [ ] **CA01**: Crear registro con datos minimos → exito
- [ ] **CA02**: Confirmar registro con lineas → state = 'confirmed'
- [ ] **CA03**: Confirmar sin lineas → UserError
- [ ] **CA04**: Modificar lineas → total se recalcula
- [ ] **CA05**: Eliminar registro draft → exito
- [ ] **CA06**: Eliminar registro confirmed → error
- [ ] **CA07**: Usuario sin permisos no puede eliminar

## Referencias al core

> Fase **specify** anclada en el core: anclajes concretos (`path:L#`) al codigo de `odoo/` o
> `enterprise/` que @researcher relevó. Sirven para que @code-dev herede/llame lo correcto y para
> que @reviewer valide firmas reales. **No inventar paths**: cada anclaje viene de @researcher.

| Que | Anclaje (`path:L#`) | Por que importa |
|-----|---------------------|-----------------|
| Modelo base a heredar | `odoo/addons/account/models/account_move.py:L120` | `_inherit = "account.move"`; firma de `_post()` |
| Metodo a extender (super) | `odoo/addons/sale/models/sale_order.py:L890` | `action_confirm()` — llamar `super()` |
| Campo reutilizable | `odoo/addons/base/models/res_partner.py:L60` | `company_id` ya existe, no redefinir |

## Documentacion afectada

> Trazabilidad de doc: que archivos de documentacion hay que crear/actualizar por esta feature.
> Cierra el loop con la regla anti-drift: si la feature altera funcionalidad visible, la doc se
> actualiza en la misma tarea (ver la tarea final del plan). @reviewer verifica que esto pase.

| Archivo | Accion | Que reflejar |
|---------|--------|-------------|
| `<modulo>/README.md` | actualizar | Nuevos modelos, flujo de usuario, modelo de seguridad |
| `<modulo>/static/description/index.html` | actualizar | Nueva funcionalidad visible (features, configuracion) |
| `<repo>/README.md` (raíz del repo de addons, según `workspace.md`) | actualizar solo si es modulo nuevo | Fila del modulo en el indice del repo |

## Plan del cambio en curso

> Descomposicion ejecutable que @code-dev consume **en orden**, respetando dependencias. Refleja el
> **cambio actual** sobre el modulo (la build inicial o la feature/modificacion que se esta
> implementando ahora). **No es acumulativo**: se reescribe en cada implementacion; una vez la spec
> queda `verified`, esta seccion puede vaciarse o ser reemplazada por el plan del proximo cambio.
> Cada tarea referencia los criterios de aceptacion que cubre y los archivos que toca.
>
> **Regla**: si el cambio altera funcionalidad visible, la ULTIMA tarea es siempre actualizar la
> documentacion (segun "Documentacion afectada"). No es opcional ni se difiere. Y la tarea de cierre
> incluye bumpear `version` en el manifest (`x.x.x`) y sincronizar la `Version` de esta spec.

| Tarea | Descripcion | Depende de | Archivos | Cubre |
|-------|-------------|------------|----------|-------|
| **T01** | Crear modelo `my.model` con campos base (name, date, state, line_ids) | — | `models/my_model.py`, `models/__init__.py` | CA01 |
| **T02** | Campo computado `total` con `@api.depends` + store | T01 | `models/my_model.py` | CA04 |
| **T03** | Metodos `action_confirm()` / `action_cancel()` + constrains | T01, T02 | `models/my_model.py` | CA02, CA03, CA06 |
| **T04** | Vistas form/list/search + accion + menu | T01 | `views/my_model_views.xml`, `views/<module>_menus.xml`, `__manifest__.py` | CA01 |
| **T05** | ACLs + grupo manager + record rule multi-compania | T01 | `security/ir.model.access.csv`, `security/<module>_security.xml` | CA05, CA07 |
| **T06** | Doc (README + index.html) + bump `version` manifest + sync `Version` spec | T01..T05 | `README.md`, `static/description/index.html`, `__manifest__.py`, `specs/<modulo>.md` | — (anti-drift + version sync) |

## Notas de implementacion

- <Decision tecnica, trade-off, o referencia a codigo core>
- <Alternativa considerada y por que se descarto>
```

## Validacion mecanica: `spec_lint.py`

Lo determinista del formato **no se verifica a mano**: `.claude/scripts/spec_lint.py <modulo>`
valida metadatos, `Estado` dentro del ciclo, `Version` formato `x.x.x` + sync con el manifest,
secciones canonicas presentes, cobertura CA↔tareas, dependencias del plan (inexistentes/ciclos) y
existencia de los anclajes `path:L#`. Lo usan @sdd-generate (auto-chequeo antes de presentar) y el
orquestador (pre-pass que inyecta a @reviewer en la fase analyze). Exit 1 si hay errores. El juicio
semantico (¿la spec dice lo correcto?) sigue siendo de @reviewer.

## Ciclo de vida de una spec

El ciclo aplica **por ciclo de cambio**: la primera vez al crear el modulo, y de nuevo (parcial)
cada vez que una modificacion vuelve a tocar la spec.

```
draft → clarified → approved → analyzed → implemented → verified

1. draft:       recien generada/editada, con huecos
2. clarified:   se resolvieron las preguntas de clarificacion (sin ambiguedad pendiente)
3. approved:    usuario la aprobo, lista para analizar/implementar
4. analyzed:    @reviewer valido consistencia interna (tareas↔modelos↔core) ANTES de codear
5. implemented: @code-dev termino de ejecutar el plan del cambio; spec editada en sitio + version sincronizada
6. verified:    @testing y @reviewer validaron la implementacion final
```

> Los estados `clarified` y `analyzed` son opcionales para cambios chicos: un cambio simple sobre un
> modulo con spec puede ir `approved → implemented → verified`. Para features grandes (muchas
> tareas, herencia de core no trivial) recorrer las 6 etapas reduce retrabajo.

## Reglas

- **Una spec por modulo**: no hay specs por feature. Las features nuevas se **funden** en la spec
  del modulo editando las secciones afectadas. Nunca crear un segundo archivo de spec en el mismo
  modulo.
- **Documento vivo, no acumulativo**: la spec describe el modulo *como esta hoy*. Editar en sitio
  (modificar la fila/seccion), nunca apilar changelog ni dejar filas contradictorias. El historial
  lo da git.
- **Spec = fuente de verdad al levantar contexto**: si el modulo tiene `specs/`, leerla ANTES de
  grepear el codigo (junto/antes que el README).
- **Version sincronizada**: la `Version` de la spec == `version` del `__manifest__.py`, en formato
  `x.x.x` (sin prefijo de serie). Cada cambio bumpea ambos al mismo valor. El reviewer y el hook
  verifican el sync.
- **Gate de conflicto**: si un cambio pedido contradice la spec, FRENAR y avisar al usuario antes de
  tocar codigo. Solo si confirma: editar la spec con la nueva decision y luego implementar.
- **Clarify antes de specify**: no se generan modelos/campos sobre requisitos ambiguos; primero
  preguntar (o marcar `[ASUNCION]`).
- **Anclar en el core**: para lo que hereda/extiende core, "Referencias al core" debe tener anclajes
  reales de @researcher (no inventar `path:L#`).
- **Plan del cambio ejecutable**: el cambio en curso se descompone en T01..Tnn con dependencias;
  @code-dev las ejecuta en orden. No es acumulativo — se reescribe por implementacion.
- **Documentacion trazable (anti-drift)**: la spec lista en "Documentacion afectada" los archivos de
  doc a actualizar, y el plan incluye la tarea final de doc + bump/sync de version si el cambio
  altera funcionalidad visible. @reviewer verifica que la doc y la version no queden mintiendo.
- **Analyze antes de implement**: para features grandes, @reviewer valida la consistencia de la spec
  antes de que @code-dev escriba codigo.
- **Spec antes de codigo**: @code-dev no empieza sin spec (para modulos que la tengan o features que
  la requieran).
- **Spec auditable**: @reviewer compara implementacion vs spec.
- **No burocracia**: specs simples para modulos simples. No sobre-especificar.
