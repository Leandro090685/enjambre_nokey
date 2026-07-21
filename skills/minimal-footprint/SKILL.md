---
name: minimal-footprint
description: Disciplina anti-over-engineering para Odoo. La escalera de decision (reusar core/framework antes que construir), los NO-negociables que nunca se recortan, y como marcar atajos deliberados. Cargar al refinar requerimientos, implementar logica de negocio o revisar codigo.
---

# Minimal Footprint — disciplina anti-over-engineering (Odoo)

> El mejor codigo es el que no se escribe. Los agentes de IA tienden a **sobre-construir**: piden un
> campo y crean un mixin abstracto; piden una validacion y agregan una dependencia. Esta skill sesga
> hacia la solucion mas chica que cumple el requisito **y** la convencion del proyecto.
>
> **No reemplaza ninguna fuente de verdad.** Las convenciones (headers, manifest, naming) viven en
> `AGENTS.md`; los patrones, en las skills `odoo-*`; los breaking changes, en `references/`. Esta
> skill solo decide *cuanto* construir, no *como*.

## La escalera de decision

Se evalua **despues** de entender el problema real. Pares en el **primer peldano** que lo resuelve;
no bajes mas si ya esta resuelto.

1. **¿Necesita existir?** (YAGNI) — ¿lo pidio el usuario o lo exige la spec? No agregues campos,
   estados, wizards, parametros de configuracion ni "ganchos para el futuro" que nadie pidio.
2. **¿Lo resuelve Odoo core/enterprise o una customizacion existente?** — antes de escribir, grepea
   el core (`grep -rl "<concepto>" <ODOO_CORE>/addons/ <ODOO_ENTERPRISE>/`) y el repo del cliente.
   Si existe, **heredá** (`_inherit` / `inherit_id`) y llamá `super()`; no reimplementes.
3. **¿Lo da el framework Odoo?** — campo `related=` o `compute` en vez de logica de sync manual;
   mixins (`mail.thread`, `mail.activity.mixin`); `ir.sequence`, `ir.cron`, `ir.actions.*`,
   `ir.config_parameter`; `Command.*` para x2many. Casi siempre hay una primitiva nativa.
4. **¿Lo cubre una dependencia/modulo ya instalado?** — revisá los `depends` actuales antes de sumar
   uno nuevo. Una dependencia nueva se justifica explicitamente o no entra.
5. **¿Puede ser minimo?** — un campo, un override chico de `create`/`write`, un `@api.constrains`,
   una linea. Preferí el cambio mas local sobre la abstraccion generica.
6. **Recien entonces: codigo minimo.** El menor codigo que cumpla el requisito **y** las convenciones
   del proyecto. Sin genericidad especulativa, sin parametrizar lo que hoy tiene un solo caso.

## NO-negociables (esto NUNCA es "bloat")

"Footprint minimo" jamas significa recortar lo que el proyecto exige por estructura. Lo siguiente va
**siempre completo**, aunque la escalera empuje a "menos":

- Encabezados (`# -*- coding: utf-8 -*-` / `<?xml ...?>`) y vim modelines.
- `README.md` + `static/description/index.html` (documentacion obligatoria).
- `ir.model.access.csv` para todo modelo nuevo; record rules donde corresponda.
- `_description` en todo `_name`; `string=` explicito en campos.
- Validaciones de negocio y mensajes con `_()` (UI en ingles).
- Seguridad: nada de saltarse ACLs/reglas ni meter `sudo()` para "simplificar".

> Espeja el blindaje del concepto original: nunca se recorta validacion, manejo de errores ni
> seguridad. En Odoo, ademas, la **estructura de modulo y la documentacion son requisito, no
> adorno**.

## Marcar atajos deliberados

Cuando elegis conscientemente la version chica y diferis algo (un edge case, una optimizacion, una
generalizacion futura), **dejalo marcado y greppable** con el motivo y el trade-off:

```python
# NOKEY: atajo deliberado — se asume un solo journal por compania; si hay multi-journal, revisar.
```
```xml
<!-- NOKEY: atajo deliberado — domain fijo; parametrizar si aparece un segundo caso de uso. -->
```

Asi el equipo encuentra la deuda con `grep -rn "NOKEY: atajo deliberado"` sin tooling extra, y
@reviewer puede validar que el trade-off sea correcto.

## Cuando NO aplicar el sesgo

- **Scaffolding de modulo nuevo** (@scaffold): la estructura completa (todas las carpetas/archivos
  base, COPYRIGHT/LICENSE, manifest) es **requisito**, no over-engineering. No la podes.
- **Generacion de documentacion** (@module-index-html, README): la doc completa es obligatoria.
- **Lo que la spec SDD ya decidio**: si una spec aprobada define un modelo/campo/metodo, eso esta
  pedido — implementalo. La escalera es para lo que NO esta especificado, no para recortar la spec.

## Donde se usa en el enjambre

| Fase | Agente | Como aplica |
|------|--------|-------------|
| Refinamiento (pre-spec) | `@feature-analyst` | "hacerlo en chico" / "no hacerlo" / reusar core como alternativas explicitas |
| Implementacion | `@code-dev` | la escalara antes de escribir logica de negocio (no la estructura obligatoria) |
| Review | `@reviewer` | lente "Footprint / anti-over-engineering" del checklist |

> El orquestador inyecta esta skill como Project Standard a `@feature-analyst` y `@code-dev` (ver
> *Skill Resolution Contract* en `CLAUDE.md`). `@reviewer` la usa como criterio de su checklist.
