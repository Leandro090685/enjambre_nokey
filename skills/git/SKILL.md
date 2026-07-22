---
name: git
description: Flujo de trabajo Git del enjambre Nokey. Modelo DIRECTO — se commitea y pushea directo sobre la rama de integración del repo (sin ramas de feature/fix, sin PR, sin aprobación). Commit/push a pedido del usuario. Única excepción: repos conectados a Odoo.sh, donde un push a la rama de deploy despliega el entorno (confirmar antes). Fuente única de la convención Git.
---

# Flujo de Trabajo Git — Nokey (directo y liviano)

> **Fuente única de verdad de la convención Git.** Todo lo demás (el agente `@git-flow`, `CLAUDE.md`,
> `ENJAMBRE.md`) **referencia** este skill, no lo repite. Si algo de la convención cambia, se edita
> **acá**.

> **Alcance**: aplica a los **repos de trabajo** (customizaciones de cliente y productos/repos
> compartidos, bajo `CLIENT_ADDONS` / `PRODUCT_ADDONS` según `workspace.md`). **No** aplica al repo
> del enjambre (`.claude/`, gestionado por `session_pull.sh`). Las operaciones las ejecuta `@git-flow`;
> **el enjambre solo corre git cuando el usuario lo pide** (commit/push).

> ✅ **Convención del enjambre Nokey (definida jul-2026): git DIRECTO, sin git flow.** No usamos ramas
> de feature/fix ni Pull Requests ni gate de aprobación: se **commitea y pushea directo** sobre la
> rama de integración del repo, con comandos git tradicionales. La única cautela es que un repo esté
> conectado a **Odoo.sh** (ver § *Excepción Odoo.sh*): ahí un push a la rama de deploy despliega el
> entorno, así que ese push se confirma con el usuario.

---

## 1. Modelo de branching

**Modelo directo (default del enjambre):** cada repo de trabajo tiene una **rama de integración**
donde vive el desarrollo, y se **trabaja, commitea y pushea directo ahí** — sin crear ramas cortas.

| Repo (ejemplos actuales) | Rama de integración | Otra rama larga | Remoto |
|--------------------------|---------------------|------------------|--------|
| `odoo_l10n_ar`, `odoo_customization_sunra` | `develop_19.0` | `19.0` | `origin` (SSH `jonathandbdb`) |
| Repo genérico sin convención propia | rama por defecto (`main`/`master`) | — | `origin` |

- **No** hay ramas `feature/`/`fix/`/`hotfix/`, **no** hay PRs, **no** hay gate de aprobación.
- Si el repo mantiene **dos ramas largas** (ej. `develop_19.0` de integración y `19.0` de
  release), se commitea en la de integración y, **si el usuario lo pide**, se replica el commit a la
  otra (§3, "Replicar a otra rama larga").
- **Detectá la rama de integración real** del repo antes de operar (no la asumas): mirá en qué rama
  está parado y las ramas que existen (`git branch -a`). Ante duda, **preguntá** en vez de inventar.

---

## 2. Prerequisitos — verificar antes de operar

1. **Estado por script**: `git_state.sh state <path>` emite toplevel, `REPO_KIND` (work/core/
   enjambre — si NO es `work`, frená), rama actual, staged, módulos tocados, y `DEPLOY_BRANCH`/
   `DEPLOY_PLATFORM` (no vacías solo si el repo declara Odoo.sh en `workspace.md` — ver § *Excepción
   Odoo.sh*).
2. `git fetch origin` para trabajar con la información remota al día.
3. Confirmá que estás parado en la **rama de integración** del repo (típ. `develop_19.0`). Si estás
   en otra rama, cambiate (`git checkout <integración>`) antes de commitear. `git pull --ff-only`
   para no divergir del remoto.
4. Si el repo no tiene una rama de integración obvia, o hay dudas de convención, **preguntale al
   usuario** en vez de inventar.

---

## 3. Comandos básicos

```bash
# Ubicarse en la rama de integración y ponerse al día
git fetch origin
git checkout develop_19.0 && git pull --ff-only     # rama de integración real del repo

# Commit: stagear archivos ESPECÍFICOS (nunca `git add .` / `-A`), revisar, commitear
git add models/foo.py views/foo_views.xml
git diff --staged                                   # revisar antes de commitear
git commit -m "[ADD] Agregar validación de fecha en foo"

# Push directo a la rama de integración
git push origin develop_19.0
```

**Replicar a otra rama larga (solo si el usuario lo pide — ej. "a develop_19.0 y a 19.0"):**
```bash
git checkout 19.0 && git merge --ff-only develop_19.0   # suelen apuntar al mismo commit → fast-forward
git push origin 19.0
git checkout develop_19.0                                # volver a la rama de integración
```
> Si el fast-forward no aplica (las ramas divergieron), **frená y consultá** — no fuerces un merge no
> trivial entre ramas largas sin confirmar.

> ⚠️ Nunca `--force` / force-push sobre ramas compartidas.

---

## 4. Commits

**Convención de mensaje: la del repo.** Antes de commitear, mirá `git log --oneline -5` y **seguí el
estilo existente**:

- **`odoo_l10n_ar` / `odoo_customization_sunra` / `sunrasa`**: prefijo **`[ADD]`** (código nuevo) /
  **`[UPD]`** (cambios sobre lo existente) + **descripción en español**, imperativa y breve. Ej.:
  ```
  [ADD] Módulo l10n_ar_partner_padron: autocompletado de contactos por CUIT
  [UPD] Ajustar redondeo del total en account.move
  ```
- **Repo sin convención propia**: mensaje claro, imperativo, un asunto por commit (podés usar
  Conventional Commits `feat:`/`fix:`/`docs:` como default razonable).
- Si el trabajo corresponde a un issue de Plane, referencialo (ej. `(#12)` al final del asunto, o
  como lo use el repo).

### Reglas de commit (seguridad e higiene)
- **Stagear archivos específicos** (`git add models/foo.py …`). **NUNCA** `git add .` ni `git add -A`.
- Revisar el stage con `git diff --staged` antes de commitear.
- **Nunca** `--amend` salvo pedido explícito. **Nunca** saltear hooks (`--no-verify`).
- Nunca commitear secrets (API keys, passwords, tokens, `.env`, configs de deploy).
- Commits atómicos; no mezclar dos asuntos distintos en un mismo commit.
- `.gitignore` del repo ya excluye `__pycache__`/`*.pyc`; igual verificá el stage.

---

## 5. Excepción Odoo.sh — push = deploy real

**La única cautela del modelo directo.** Si un repo está conectado a **Odoo.sh** (u otra plataforma
que despliega por push), un `git push` a la rama larga **deploya el entorno**. Se declara con markers
opcionales en `workspace.md` (§ Deploy): `DEPLOY_PLATFORM`, `PROD_BRANCH`/`STAGING_BRANCH` + URLs.
`git_state.sh` los resuelve y emite `DEPLOY_BRANCH=yes` cuando estás parado en una de esas ramas.

- **Con markers declarados** (repo Odoo.sh): un push a `PROD_BRANCH` o `STAGING_BRANCH` **despliega
  producción / staging**. Ese push se confirma **explícitamente con el usuario** antes de correrlo
  (avisá qué entorno se va a desplegar y su URL). Ante la duda → `NEEDS_INPUT`.
- **Sin markers** (el caso normal de los repos de addons `odoo_l10n_ar`/`odoo_customization_sunra`,
  en `develop_19.0`): el push es un push común de GitHub, no deploya nada → directo, sin ceremonia.

> Esto **no** reintroduce git flow: no hay ramas de feature ni PRs. Es solo "pensar antes de pushear
> a una rama que auto-despliega".

### 5.1 Repo agregador con submódulos (patrón Odoo.sh)

Un repo Odoo.sh suele ser un **agregador**: no tiene código propio, sino que referencia a los repos
de addons como **submódulos** (pinneados a un commit; con `branch=` en `.gitmodules`). Es el caso de
**`sunrasa`** en este workspace (submódulos `odoo_l10n_ar` + `odoo_customization_sunra`; ramas de
entorno `stagesunra`/`main`; checkouts de referencia `staging/sunrasa` / `produccion/sunrasa` — datos
concretos en `workspace.md` § Deploy).

Consecuencia clave: **el Odoo local carga los addons directo de `extra-addons/`, pero Odoo.sh deploya
el agregador.** Pushear el repo del addon (`odoo_l10n_ar` @ `develop_19.0`) **no** deploya nada por sí
solo — hay que **bumpear el pin del submódulo** en el agregador y pushear la rama de entorno:

```bash
# Tras clonar/pull del agregador, poblar submódulos:
git -C staging/sunrasa submodule update --init --recursive
# Deployar a staging el estado actual de los addons:
cd staging/sunrasa
git submodule update --remote                 # trae la punta de develop_19.0 de cada submódulo
git add <submodulo> && git commit -m "Actualiza submodulo <x> a develop_19.0 (...)"
git push origin <STAGING_BRANCH>              # ⚠️ deploya staging — confirmar con el usuario
```
**Cada rama de entorno del agregador rastrea su propia rama de submódulo** (no es una promoción de la
otra): staging → los addons en su rama de integración (`develop_19.0`); producción → los addons en su
rama de release (`19.0`). Se arma con `git submodule add -b <rama> <url> <path>`. Deployar producción
= en el checkout de prod, `git submodule update --remote` (trae la punta de `19.0`) + commit del pin +
`git push origin <PROD_BRANCH>` (⚠️ deploya prod — confirmar). Convención de commit del agregador: la
del repo (mirá `git log`).

---

## 6. Multi-repo

Cuando una tarea toca varios repos a la vez:
- Procesar los repos **secuencialmente**, verificando éxito en cada uno antes de seguir.
- Si uno falla, **frenar y reportar** — no seguir a ciegas.
- Reportar éxito/fallo por repo.

---

## 7. Resolución de conflictos

1. Poné al día la rama de integración: `git fetch origin && git checkout develop_19.0 && git pull --ff-only`.
2. Si el push fue rechazado por estar atrasado, integrá el remoto (`git pull --ff-only`; si no
   fast-forwardea, `git pull --rebase` o resolver el merge) y reintentá el push.
3. Resolver conflictos manualmente.
4. Validar (`py_compile` + `xmllint`; los hooks del enjambre validan al escribir).
5. Commit del merge/rebase y `git push`.

> Ante un conflicto no trivial o estado ambiguo → **frená y consultá** (`BLOCKED`/`NEEDS_INPUT`);
> nunca resolver a ciegas ni borrar trabajo.

---

## 8. Versionado de módulos (manifest + SDD)

`__manifest__.py` usa **`x.x.x` simple**, **sin** prefijo de serie de Odoo (Odoo la antepone en runtime):
```python
"version": "1.0.0",   # major=breaking, minor=feature, patch=fix
```
> ⚠️ `19.0.1.0.0` está **desaconsejado** y `{serie}.1.0.0` deja el módulo **uninstallable**. Ver `AGENTS.md` § Manifest.

> 🔗 **Módulos SDD**: si el módulo tiene `specs/`, el `version` del manifest debe quedar **igual** a la
> `Version` de la spec tras cada cambio (skill `sdd-specification`). El commit que bumpea la versión
> sincroniza la spec en el mismo cambio.

---

## 9. Quick Reference

| Acción | Comando |
|--------|---------|
| Ubicarse en integración | `git checkout develop_19.0 && git pull --ff-only` |
| Ver convención de commit del repo | `git log --oneline -5` |
| Commit (archivos específicos) | `git add <files> && git commit -m "[ADD] …"` (ver §4) |
| Push directo (a pedido) | `git push origin develop_19.0` |
| Replicar a otra rama larga (a pedido) | `git checkout 19.0 && git merge --ff-only develop_19.0 && git push origin 19.0` |
| Repo Odoo.sh (con markers) | push a rama de deploy = **deploy real** → confirmar con el usuario (§5) |
| Deploy Odoo.sh (agregador) | en `staging/sunrasa`: `git submodule update --remote` → `git add <sub> && commit` → `git push origin <STAGING_BRANCH>` = **deploy staging** (§5.1) |
| Multi-repo | secuencial, un repo a la vez, frenar si uno falla (§6) |
