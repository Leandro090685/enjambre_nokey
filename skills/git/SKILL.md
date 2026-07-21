---
name: git
description: Flujo de trabajo Git del enjambre Nokey. Branch-first (feature/fix desde staging, hotfix desde prod), commits claros, PRs vía gh/GitHub, releases staging→prod a pedido. Soporta ramas de deploy Odoo.sh declaradas en workspace.md (PROD_BRANCH/STAGING_BRANCH). Fuente única de la convención Git.
---

# Flujo de Trabajo Git — Nokey (genérico y liviano)

> **Fuente única de verdad de la convención Git.** Todo lo demás (el agente `@git-flow`, `CLAUDE.md`,
> `ENJAMBRE.md`) **referencia** este skill, no lo repite. Si algo de naming/commit/PR cambia, se edita
> **acá**.

> **Alcance**: aplica a los **repos de trabajo** (customizaciones de cliente y productos/repos
> compartidos, bajo `CLIENT_ADDONS` / `PRODUCT_ADDONS` según `workspace.md`). **No** aplica al repo
> del enjambre (`.claude/`, gestionado por `session_pull.sh`). Las operaciones las ejecuta `@git-flow`;
> **el enjambre solo corre git cuando el usuario lo pide** (commit/push/PR/merge), salvo el
> *branch-first* (asegurar la rama de trabajo antes de escribir), que es automático.

> ✅ **Convención del repo cliente (Sunra/sunrasa): definida (jul-2026).** El repo está conectado a
> **Odoo.sh** y usa el modo **staging/prod** de abajo: `main` = producción (https://miluan.odoo.com),
> `stagesunra` = staging (https://stage-miluan.odoo.com). Los markers `PROD_BRANCH`/`STAGING_BRANCH`/
> `PROD_URL`/`STAGING_URL`/`DEPLOY_PLATFORM` viven en `workspace.md` (§ Deploy) — este skill no
> hardcodea nombres: siempre los resuelve de ahí (`git_state.sh` ya los emite).

---

## 1. Modelo de branching

El modelo depende de si el workspace declara ramas de deploy (`STAGING_BRANCH`/`PROD_BRANCH` en
`workspace.md`):

**Modo simple** (sin markers): una sola rama larga — la rama por defecto del repo (`main`/`master`).
`feature/`/`fix/` nacen de ella y sus PRs apuntan ahí.

**Modo staging/prod** (markers declarados — el caso de sunrasa, en Odoo.sh):

| Rama | Rol | Nace de | PR / merge a |
|------|-----|---------|--------------|
| `PROD_BRANCH` (ej. `main`) | **Producción**, desplegada (Odoo.sh la deploya al mergear). Nunca trabajar directo. | — | — |
| `STAGING_BRANCH` (ej. `stagesunra`) | **Staging/integración**, desplegada en la URL de staging. Nunca trabajar directo. | — | — |
| **feature** `feature/<slug>` | Nueva funcionalidad / cambio no urgente. | staging | staging |
| **fix** `fix/<slug>` | Corrección de bug no urgente (aún no en prod, o puede esperar el release). | staging | staging |
| **hotfix** `hotfix/<slug>` | Corrección **urgente de producción**. | **prod** | **prod** + back-merge a staging |
| **release** (promoción, no es una rama) | Pasaje staging → prod + tag. **Solo a pedido explícito.** | — | PR staging → prod |

> 🔴 **Regla dura**: SIEMPRE se trabaja en una rama corta. **NUNCA** se commitea/trabaja directo
> sobre las ramas largas (`main`/`master`, `PROD_BRANCH` ni `STAGING_BRANCH`).
>
> ⚠️ **En Odoo.sh, merge a rama larga = deploy real**: mergear a staging deploya el entorno de
> staging; mergear a prod deploya producción. Por eso el merge a staging pide confirmación normal,
> y **todo lo que toque `PROD_BRANCH` (release/hotfix-merge) exige pedido explícito del usuario** —
> nunca es iniciativa del enjambre.

Sin `git flow` (la herramienta): el modelo se opera con git plano + `gh`, como en el resto del skill.

---

## 2. Prerequisitos — verificar antes de operar

1. **Resolvé las ramas base**: `git_state.sh state <path>` emite `STAGING_BRANCH`/`PROD_BRANCH`
   (de `workspace.md`). Si están vacías → modo simple: detectá la rama por defecto real del repo
   (`main`, `master`, u otra) — no la asumas.
2. `git fetch origin` para trabajar con la información remota al día.
3. Confirmá en qué rama estás parado. Si es una rama larga (por defecto, staging o prod) → crear una
   rama de trabajo ANTES de tocar código (branch-first). Si ya estás en una `feature/`/`fix/`/
   `hotfix/` correcta → seguí ahí.
4. Si el repo no tiene un nombre de rama por defecto obvio, o hay dudas de convención, **preguntale al
   usuario** en vez de inventar.

---

## 3. Comandos básicos

```bash
# Actualizar y crear rama de trabajo — feature/fix nacen de STAGING (stagesunra en sunrasa;
# en modo simple, de la rama por defecto). Salvo que el usuario diga lo contrario.
git fetch origin
git checkout stagesunra && git pull --ff-only   # STAGING_BRANCH real según workspace.md
git checkout -b feature/<slug>                  # o fix/<slug>

# Hotfix: nace de PRODUCCIÓN (main), no de staging
git checkout main && git pull --ff-only
git checkout -b hotfix/<slug>

# Publicar (push) la rama
git push -u origin feature/<slug>

# Traer cambios nuevos de la rama base a la rama de trabajo
git fetch origin
git merge origin/stagesunra                     # (hotfix: origin/main) — conflictos: ver §8
```

> ⚠️ Nunca `--force` / force-push sobre ramas compartidas. Nunca trabajar parado en una rama larga.

---

## 4. Naming de branches

```
feature/<#seq>-<slug>          # ej. feature/12-add-partner-vat-check  (con issue de Plane)
fix/<#seq>-<slug>              # ej. fix/15-wrong-total-rounding
hotfix/<#seq>-<slug>           # ej. hotfix/18-broken-invoice-post     (urgente, nace de prod)
feature/<slug-descriptivo>     # sin issue trackeado (excepción — lo normal es que haya issue)
```

- `<slug>` en minúsculas, palabras separadas por guion medio, descriptivo y corto, en inglés.
- **`<#seq>` = número de issue de Plane** (skill `plane-tracking`): si la tarea tiene issue (lo
  normal — el trabajo se gestiona en Plane), el número va **al inicio del slug**. Eso ata rama ↔
  issue y permite que los comentarios de avance en Plane referencien la rama sin ambigüedad.
- Si no hay issue todavía, el enjambre puede crearlo primero (flujo "Trabaja la tarea", CLAUDE.md)
  y usar su número; solo si el usuario no quiere trackear el trabajo se usa el slug pelado.

---

## 5. Commits

Sin convención propietaria heredada: mensajes **claros, en modo imperativo, un asunto por commit**.
Como default razonable (ajustable cuando el equipo defina algo distinto), se recomienda
**Conventional Commits**:

```
<tipo>: <descripción breve>

<tipo> ∈ feat | fix | refactor | docs | test | chore
```

Ejemplos:
```
feat: agregar validación de VAT en res.partner
fix: corregir redondeo del total en my_model
docs: actualizar README del módulo sale_extension
```

✅ **Convención sunrasa (jul-2026)**: Conventional Commits, y si el trabajo corresponde a un issue
de Plane, referencialo al final del asunto con `(#<seq>)`:

```
feat: agregar validación de VAT en res.partner (#12)
```

### Reglas de commit (seguridad e higiene)
- **Stagear archivos específicos** (`git add models/foo.py …`). **NUNCA** `git add .` ni `git add -A`.
- Revisar el stage con `git diff --staged` antes de commitear.
- **Nunca** `--amend` salvo pedido explícito. **Nunca** saltear hooks (`--no-verify`).
- Nunca commitear secrets (API keys, passwords, tokens, `.env`, configs de staging/prod).
- Commits atómicos; no mezclar dos asuntos distintos en un mismo commit.

---

## 6. Pull Requests (vía `gh`/GitHub)

**Título**: descriptivo y corto (ej. `Agregar validación de VAT en Partner`).

**Abrir el PR** con `gh` (CLI de GitHub) — **solo a pedido del usuario** (publish/PR no es
automático):

```bash
gh pr create \
  --base stagesunra \
  --title "Agregar validación de VAT en Partner (#12)" \
  --body "$(cat <<'EOF'
## Qué se hizo
- ...

## Módulos afectados
- <modulo>

## Issue
- Plane #12

## Testing
- [ ] py_compile / xmllint sin errores
EOF
)"
```

**Destino (`--base`) según el tipo de rama** — en modo staging/prod NO uses el default de `gh`
(apuntaría a la rama por defecto del repo, que puede ser prod):

| Rama origen | `--base` |
|-------------|----------|
| `feature/*` / `fix/*` | `STAGING_BRANCH` (ej. `stagesunra`) — se valida en la URL de staging |
| `hotfix/*` | `PROD_BRANCH` (ej. `main`) — ⚠️ el merge deploya producción |
| release (promoción) | `PROD_BRANCH`, con head `STAGING_BRANCH` (ver §7bis) |

En modo simple (sin markers), el default de `gh` (rama por defecto del repo) está bien.

**Ciclo de review**: las correcciones van **en la misma rama** y se suben con `git push` → quedan en
el **mismo PR**. Una vez **aprobado**, se fusiona (`gh pr merge` o el botón de merge de GitHub, según
la práctica del equipo).

```bash
gh pr merge --squash    # o --merge / --rebase, según la práctica del equipo — a pedido del usuario
```

> No hay automatización de notificaciones (sin Discord) ni de sistemas de gestión de tareas externos
> (sin Odoo PM/Bitbucket): el flujo termina en el PR de GitHub. Si el cliente adopta alguna
> integración a futuro, se agrega acá.

---

## 7. Finalizar ramas (merge) + multi-repo

### Finish
Mergear la rama de trabajo a su rama destino (vía `gh pr merge` o el botón de la plataforma) es la
operación más destructiva sobre el historial compartido → **confirmá SIEMPRE con el usuario antes**
(y en Odoo.sh además deploya el entorno de esa rama). Tras el merge, actualizá tu copia local:
```bash
git checkout stagesunra && git pull --ff-only   # la rama destino real (staging, o main si hotfix)
git branch -d feature/<slug>          # borrar la rama local ya integrada
```

### Hotfix — cierre completo (prod + back-merge)
Un hotfix mergeado a `PROD_BRANCH` debe volver también a `STAGING_BRANCH` para que el próximo
release no lo pise (el equivalente del doble-merge de git-flow):
```bash
# 1. PR hotfix/<slug> → main, merge (a pedido, deploya prod)
# 2. Back-merge a staging (PR main → stagesunra, o merge directo si el equipo lo permite):
git checkout stagesunra && git pull --ff-only
git merge origin/main                 # trae el hotfix a staging
git push origin stagesunra            # ⚠️ deploya staging — avisar al usuario
```

---

## 7bis. Release — promoción staging → producción (SOLO a pedido)

> El usuario pide "deployá a producción" / "hacé el release". **Nunca** es iniciativa del enjambre.
> En Odoo.sh el merge a `PROD_BRANCH` **deploya producción** (https://miluan.odoo.com en sunrasa).

1. **Precondiciones**: staging al día y verde (lo mergeado se validó en la URL de staging;
   `git fetch origin` y confirmar que `PROD_BRANCH` no tiene commits que staging no tenga — si los
   tiene, primero back-merge prod→staging y resolver).
2. **PR de promoción**: `gh pr create --base main --head stagesunra --title "Release YYYY-MM-DD"`
   con body que liste los cambios incluidos (issues de Plane `#seq`, módulos y versiones).
3. **Merge tras aprobación** (confirmación explícita del usuario — es el deploy de prod). Usar
   **merge commit** (`gh pr merge --merge`), NO squash: staging y prod deben quedar con la misma
   historia para que el próximo release no arrastre conflictos.
4. **Tag** sobre el merge en prod: `release/YYYY-MM-DD` (si hay dos el mismo día: `-2`, `-3`, …):
   ```bash
   git checkout main && git pull --ff-only
   git tag -a release/2026-07-21 -m "Release 2026-07-21: <resumen corto>"
   git push origin release/2026-07-21
   ```
5. **Verificar el deploy**: Odoo.sh reconstruye producción; confirmar en `PROD_URL` que levantó.
6. **Plane**: comentar en los issues incluidos que quedaron **en producción** (con el tag y la
   fecha); si el proyecto distingue "Done" vs "deployado", es solo comentario — no hay estado extra.

### Operaciones multi-repo
Cuando una tarea toca varios repos a la vez:
- Usar **el mismo nombre de rama** en todos los repos si tiene sentido (mismo slug).
- Procesar los repos **secuencialmente**, verificando éxito en cada uno antes de seguir.
- Si uno falla, **frenar y reportar** — no seguir a ciegas.
- Reportar éxito/fallo por repo.

---

## 8. Resolución de conflictos

1. Actualizar la rama base local (staging para feature/fix; prod para hotfix):
   `git fetch origin && git checkout stagesunra && git pull --ff-only`
2. Traer la rama base a la rama de trabajo: `git checkout feature/<slug> && git merge stagesunra`
3. Resolver conflictos
4. Validar (`py_compile` + `xmllint`; los hooks del enjambre validan al escribir)
5. Commit del merge y `git push`

---

## 9. Versionado de módulos (manifest + SDD)

`__manifest__.py` usa **`x.x.x` simple**, **sin** prefijo de serie de Odoo (Odoo la antepone en runtime):
```python
"version": "1.0.0",   # major=breaking, minor=feature, patch=fix
```
> ⚠️ `19.0.1.0.0` está **desaconsejado** y `{serie}.1.0.0` deja el módulo **uninstallable**. Ver `AGENTS.md` § Manifest.

> 🔗 **Módulos SDD**: si el módulo tiene `specs/`, el `version` del manifest debe quedar **igual** a la
> `Version` de la spec tras cada cambio (skill `sdd-specification`). El commit que bumpea la versión
> sincroniza la spec en el mismo cambio.

> ✅ **Tags de release a nivel repo (sunrasa, jul-2026)**: `release/YYYY-MM-DD` (anotado), creado
> sobre `PROD_BRANCH` en cada promoción a producción — ver §7bis. Los módulos siguen versionando
> por manifest (`x.x.x`); el tag marca el snapshot del repo que quedó desplegado.

---

## 10. Quick Reference

| Acción | Comando |
|--------|---------|
| Nueva rama de feature/fix | `git checkout -b feature/<#seq>-<slug>` (desde **staging** actualizada) |
| Nueva rama de hotfix | `git checkout -b hotfix/<#seq>-<slug>` (desde **prod** actualizada) |
| Publicar (push) | `git push -u origin <rama>` |
| Abrir PR (a pedido) | `gh pr create --base <staging \| prod si hotfix> --title "... (#seq)"` |
| Actualizar PR | `git push` sobre la misma rama |
| Finalizar (merge, con confirmación) | `gh pr merge --squash` (feature/fix) + `git pull` en local |
| Release a producción (a pedido) | PR `staging → prod` + `--merge` + tag `release/YYYY-MM-DD` (§7bis) |
| Back-merge de hotfix | merge `prod → staging` tras el hotfix (§7) |
| Commit | `<tipo>: <descripción> (#seq)` (Conventional Commits — ver §5) |
