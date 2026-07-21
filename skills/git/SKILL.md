---
name: git
description: Flujo de trabajo Git genérico y liviano para el enjambre Nokey. Branch-first (ramas feature/fix), commits claros, PRs vía gh/GitHub. Sin git-flow, sin ramas largas por versión, sin integraciones propietarias. Fuente única de la convención Git.
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

> ⚠️ **Convención exacta del repo cliente (Sunra/sunrasa): `[POR DEFINIR]`.** Este skill documenta un
> flujo genérico razonable (branch-first + feature/fix + PR vía `gh`). En cuanto el equipo defina su
> convención real (naming de ramas, formato de commit, revisores, si usa tags de release), actualizá
> este documento — es la fuente única.

---

## 1. Modelo de branching (sin ramas largas por versión)

A diferencia de un esquema Gitflow con ramas largas por serie, acá el modelo es simple:

| Rama | Rol |
|------|-----|
| Rama por defecto (`main`/`master`, la que use el repo) | Estable. **Nunca trabajar directo.** |
| **feature** `feature/<slug>` | Nueva funcionalidad / cambio no urgente. Nace de la rama por defecto. |
| **fix** `fix/<slug>` | Corrección de bug. Nace de la rama por defecto. |

> 🔴 **Regla dura**: SIEMPRE se trabaja en una rama corta. **NUNCA** se commitea/trabaja directo sobre
> `main`/`master` (ni sobre la rama por defecto que use el repo, sea cual sea su nombre real).

Sin `git flow`, sin ramas largas nombradas por versión de Odoo, sin distinción hotfix/release: si en
algún momento el repo del cliente necesita ramas de release o de soporte de una versión en producción,
eso se define y se documenta acá cuando surja la necesidad real (no se anticipa).

---

## 2. Prerequisitos — verificar antes de operar

1. **Detectá la rama por defecto real** del repo (`main`, `master`, u otra) — no la asumas.
2. `git fetch origin` para trabajar con la información remota al día.
3. Confirmá en qué rama estás parado. Si es la rama por defecto → crear una rama de trabajo ANTES de
   tocar código (branch-first). Si ya estás en una `feature/`/`fix/` correcta → seguí ahí.
4. Si el repo no tiene un nombre de rama por defecto obvio, o hay dudas de convención, **preguntale al
   usuario** en vez de inventar.

---

## 3. Comandos básicos

```bash
# Actualizar y crear rama de trabajo (nace de la rama por defecto, al día)
git fetch origin
git checkout main && git pull --ff-only        # o master / la rama por defecto real del repo
git checkout -b feature/<slug>                 # o fix/<slug>

# Publicar (push) la rama
git push -u origin feature/<slug>

# Traer cambios nuevos de la rama por defecto a la rama de trabajo
git fetch origin
git merge origin/main                          # resolver conflictos si aparecen (ver §8)
```

> ⚠️ Nunca `--force` / force-push sobre ramas compartidas. Nunca trabajar parado en la rama por
> defecto.

---

## 4. Naming de branches

```
feature/<slug-descriptivo>     # ej. feature/add-partner-vat-check
fix/<slug-descriptivo>         # ej. fix/wrong-total-rounding
```

- `<slug>` en minúsculas, palabras separadas por guion medio, descriptivo y corto.
- ⚠️ `[POR DEFINIR]`: si el cliente usa un tracker de tareas (issues de GitHub, tablero externo) y
  quiere el número de tarea en el nombre de la rama (ej. `feature/123-add-partner-vat-check`),
  actualizá esta sección con esa convención en cuanto se defina.

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

⚠️ `[POR DEFINIR]`: si el repo del cliente (sunrasa) ya tiene su propio formato de commit (con o sin
prefijo de tarea/ticket), seguí ese en vez de Conventional Commits — actualizá esta sección cuando se
confirme.

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
  --title "Agregar validación de VAT en Partner" \
  --body "$(cat <<'EOF'
## Qué se hizo
- ...

## Módulos afectados
- <modulo>

## Testing
- [ ] py_compile / xmllint sin errores
EOF
)"
# Por default usa la rama actual como origen y detecta el destino (rama por defecto del repo).
# Override si hace falta: --base <rama> --head <rama>.
```

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
Mergear la rama de trabajo a la rama por defecto (vía `gh pr merge` o el botón de la plataforma) es la
operación más destructiva sobre el historial compartido → **confirmá SIEMPRE con el usuario antes**.
Tras el merge, actualizá tu copia local:
```bash
git checkout main && git pull --ff-only
git branch -d feature/<slug>          # borrar la rama local ya integrada
```

### Operaciones multi-repo
Cuando una tarea toca varios repos a la vez:
- Usar **el mismo nombre de rama** en todos los repos si tiene sentido (mismo slug).
- Procesar los repos **secuencialmente**, verificando éxito en cada uno antes de seguir.
- Si uno falla, **frenar y reportar** — no seguir a ciegas.
- Reportar éxito/fallo por repo.

---

## 8. Resolución de conflictos

1. Actualizar la rama por defecto local: `git fetch origin && git checkout main && git pull --ff-only`
2. Traer la rama por defecto a la rama de trabajo: `git checkout feature/<slug> && git merge main`
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

> ⚠️ `[POR DEFINIR]`: tags de release a nivel repo (no manifest) — si el cliente los adopta, documentar
> acá el formato exacto.

---

## 10. Quick Reference

| Acción | Comando |
|--------|---------|
| Nueva rama de feature | `git checkout -b feature/<slug>` (desde la rama por defecto actualizada) |
| Nueva rama de fix | `git checkout -b fix/<slug>` |
| Publicar (push) | `git push -u origin <rama>` |
| Abrir PR (a pedido) | `gh pr create --title "..." --body "..."` |
| Actualizar PR | `git push` sobre la misma rama |
| Finalizar (merge, con confirmación) | `gh pr merge --squash` (o equivalente) + `git pull` en local |
| Commit | `<tipo>: <descripción>` (Conventional Commits, default — ver §5) |
