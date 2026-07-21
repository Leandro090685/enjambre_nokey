#!/bin/bash
# scripts/salud.sh — chequeo de salud del entorno del enjambre Nokey (comando /salud).
# Valida que el workspace este bien configurado: workspace.md, ODOO_VERSION, paths declarados,
# references de la version, hooks, symlink de CLAUDE.md, Docker y git. Read-only.
# Salida: checklist [OK]/[WARN]/[FAIL] + resumen. Exit 1 si hay algun FAIL (sirve para onboarding/CI).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/../hooks/lib.sh" 2>/dev/null || { echo "[FAIL] No se pudo cargar hooks/lib.sh"; exit 1; }

OK_N=0; WARN_N=0; FAIL_N=0
ok()   { OK_N=$((OK_N+1));     printf '  [OK]   %s\n' "$1"; }
warn() { WARN_N=$((WARN_N+1)); printf '  [WARN] %s\n' "$1"; }
fail() { FAIL_N=$((FAIL_N+1)); printf '  [FAIL] %s\n' "$1"; }

root="$(swarm_workspace_root)"

echo "=== SALUD — salud del entorno Nokey ==="
echo

echo "── Configuracion ──"
ws="$(swarm_workspace_file)"
if [ -z "$ws" ]; then
    fail "No hay workspace.md ni workspace.example.md en .claude/ — copiá workspace.example.md a workspace.md"
elif [ "$(basename "$ws")" = "workspace.example.md" ]; then
    warn "Usando workspace.example.md (plantilla): copiá a .claude/workspace.md y describí tu entorno"
else
    ok "workspace.md presente"
fi

ver="$(swarm_ws_marker ODOO_VERSION)"
if [ -z "$ver" ]; then
    fail "ODOO_VERSION no declarada en workspace.md (los hooks de breaking-changes la necesitan)"
elif ! printf '%s' "$ver" | grep -qE '^[0-9]+$'; then
    fail "ODOO_VERSION='$ver' no es numerica (esperado p.ej. 19)"
else
    ok "ODOO_VERSION = $ver"
fi

par_raw="$(swarm_ws_marker PARALLELISM)"
if [ -n "$par_raw" ] && ! printf '%s' "$par_raw" | grep -qE '^(off|readonly|full)$'; then
    warn "PARALLELISM='$par_raw' no es off|readonly|full — rige el default (readonly)"
else
    ok "PARALLELISM = $(swarm_parallelism)$([ -z "$par_raw" ] && echo ' (default)')"
fi

echo
echo "── Paths declarados (handles) ──"
check_paths() {  # $1 = etiqueta, resto via stdin (paths absolutos)
    local label="$1" p missing=0 total=0
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        total=$((total+1))
        [ -d "$p" ] || { fail "$label: no existe -> ${p#"$root"/}"; missing=$((missing+1)); }
    done
    [ "$total" -gt 0 ] && [ "$missing" -eq 0 ] && ok "$label: $total path(s) existen"
    [ "$total" -eq 0 ] && warn "$label: ninguno declarado (se usan defaults por estructura)"
}
check_paths "CORE_ROOTS"    < <(swarm_core_roots)
check_paths "CLIENT_ADDONS" < <(swarm_client_addons)
check_paths "PRODUCT_ADDONS" < <(swarm_product_addons)

echo
echo "── References de la version ──"
if [ -n "$ver" ] && printf '%s' "$ver" | grep -qE '^[0-9]+$'; then
    [ -f "$NOKEY_CLAUDE_DIR/references/v${ver}_gotchas.md" ] \
        && ok "references/v${ver}_gotchas.md" \
        || warn "Falta references/v${ver}_gotchas.md (gotchas curados de la version)"
    [ -f "$NOKEY_CLAUDE_DIR/references/patterns/v${ver}.patterns" ] \
        && ok "references/patterns/v${ver}.patterns" \
        || warn "Falta references/patterns/v${ver}.patterns (el hook de breaking-changes no bloqueara)"
fi

echo
echo "── Hooks y symlink ──"
nx=0
for f in "$NOKEY_CLAUDE_DIR"/hooks/*.sh; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "lib.sh" ] && continue   # libreria sourced, no se ejecuta
    [ -x "$f" ] || { warn "Hook sin permiso de ejecucion: hooks/$(basename "$f") (chmod +x)"; nx=$((nx+1)); }
done
[ "$nx" -eq 0 ] && ok "Hooks ejecutables"
# Scripts de automatizacion del enjambre (los invocan agentes/orquestador; sin ellos los agentes
# caen al procedimiento manual — no rompe, pero pierde el ahorro de tokens)
na=0
for s in odoo_runtime.sh cliente.sh git_state.sh extract_docx.sh spec_lint.py review_static.sh; do
    f="$NOKEY_CLAUDE_DIR/scripts/$s"
    if [ ! -f "$f" ]; then warn "falta scripts/$s (agente cae a procedimiento manual)"; na=$((na+1));
    elif [ ! -x "$f" ]; then warn "scripts/$s sin permiso de ejecucion (chmod +x)"; na=$((na+1)); fi
done
[ "$na" -eq 0 ] && ok "scripts de automatizacion presentes y ejecutables"
if [ -e "$root/CLAUDE.md" ]; then
    ok "CLAUDE.md en la raiz presente"
else
    warn "No hay CLAUDE.md en la raiz del workspace (symlink a .claude/CLAUDE.md)"
fi

echo
echo "── Consistencia interna (enjambre) ──"
# Valida que la doc del enjambre (CLAUDE.md / ENJAMBRE.md) no driftee de lo que existe en disco:
# agentes referenciados ↔ archivos, modelo declarado ↔ frontmatter, skills con SKILL.md, conteos.
cmd="$NOKEY_CLAUDE_DIR/CLAUDE.md"
enj="$NOKEY_CLAUDE_DIR/ENJAMBRE.md"
if [ ! -f "$cmd" ]; then
    warn "No se encontro .claude/CLAUDE.md — no se puede validar coherencia agentes/skills"
else
    # Agentes de la tabla de CLAUDE.md (| @nombre | modelo | ...) vs archivos en agents/
    missing_ag=0; modeldrift=0
    while IFS=$'\t' read -r name tbl_model; do
        [ -n "$name" ] || continue
        af="$NOKEY_CLAUDE_DIR/agents/$name.md"
        if [ ! -f "$af" ]; then
            fail "CLAUDE.md referencia @$name pero falta agents/$name.md"
            missing_ag=$((missing_ag+1)); continue
        fi
        fm_model=$(sed -nE 's/^model:[[:space:]]*([A-Za-z0-9._-]+).*/\1/p' "$af" | head -1)
        if [ -n "$fm_model" ] && [ -n "$tbl_model" ] && [ "$fm_model" != "$tbl_model" ]; then
            warn "Drift de modelo en @$name: tabla CLAUDE.md='$tbl_model' vs frontmatter='$fm_model'"
            modeldrift=$((modeldrift+1))
        fi
    done < <(awk -F'|' '/^\|[[:space:]]*@/{n=$2;m=$3;gsub(/[[:space:]@]/,"",n);gsub(/[[:space:]]/,"",m);if(n!="")print n"\t"m}' "$cmd")
    [ "$missing_ag" -eq 0 ] && ok "Agentes de CLAUDE.md presentes en agents/"
    [ "$modeldrift" -eq 0 ] && ok "Modelo de cada agente coincide (tabla CLAUDE.md ↔ frontmatter)"

    # Agentes en agents/ que NO figuran en la tabla de CLAUDE.md (huerfanos)
    orphan_ag=0
    for af in "$NOKEY_CLAUDE_DIR"/agents/*.md; do
        [ -f "$af" ] || continue
        an="$(basename "$af" .md)"
        grep -qE "^\|[[:space:]]*@$an[[:space:]]*\|" "$cmd" \
            || { warn "agents/$an.md no figura en la tabla de CLAUDE.md"; orphan_ag=$((orphan_ag+1)); }
    done
    [ "$orphan_ag" -eq 0 ] && ok "Sin agentes huerfanos en agents/"
fi

# Skills: cada subcarpeta de skills/ debe tener su SKILL.md (si no, no carga)
missing_sk=0; sk_total=0
for sd in "$NOKEY_CLAUDE_DIR"/skills/*/; do
    [ -d "$sd" ] || continue
    sk_total=$((sk_total+1))
    [ -f "${sd}SKILL.md" ] || { fail "skills/$(basename "$sd")/ sin SKILL.md (no cargara)"; missing_sk=$((missing_sk+1)); }
done
[ "$missing_sk" -eq 0 ] && [ "$sk_total" -gt 0 ] && ok "Skills: $sk_total con SKILL.md"

# Drift de conteo de skills en la tabla resumen de ENJAMBRE.md ("| Skills | N |")
if [ -f "$enj" ] && [ "$sk_total" -gt 0 ]; then
    claimed=$(grep -oiE '\|[[:space:]]*Skills[[:space:]]*\|[[:space:]]*[0-9]+' "$enj" | grep -oE '[0-9]+' | head -1)
    if [ -n "$claimed" ] && [ "$claimed" != "$sk_total" ]; then
        warn "ENJAMBRE.md declara $claimed skills pero hay $sk_total en skills/ — actualizar ENJAMBRE.md"
    elif [ -n "$claimed" ]; then
        ok "ENJAMBRE.md: conteo de skills coincide ($sk_total)"
    fi
fi

echo
echo "── Contenedor (Odoo) ──"
container="$(swarm_ws_marker ODOO_CONTAINER)"
engine="$(swarm_container_engine)"
if [ -z "$container" ]; then
    warn "Sin marcador ODOO_CONTAINER en workspace.md (opcional; habilita el chequeo del contenedor)"
elif ! command -v "$engine" >/dev/null 2>&1; then
    warn "ODOO_CONTAINER declarado ($container) pero el engine '$engine' no esta disponible aca"
else
    case "$(swarm_docker_status)" in
        up)   ok "Contenedor '$container' corriendo ($engine)" ;;
        *)    warn "Contenedor '$container' declarado pero no esta corriendo ($engine start $container)" ;;
    esac
fi

echo
echo "── Secretos (opcional) ──"
# Cargar secretos del archivo (NOKEY_SECRETS_FILE, fuera del repo) para chequear su presencia abajo.
command -v swarm_load_secrets >/dev/null 2>&1 && swarm_load_secrets
secrets_f="$(command -v swarm_secrets_file >/dev/null 2>&1 && swarm_secrets_file || echo "$HOME/.claude/nokey-enjambre-secrets.env")"
if [ -f "$secrets_f" ]; then
    ok "archivo de secretos presente (${secrets_f/#$HOME/~})"
else
    warn "no hay archivo de secretos (${secrets_f/#$HOME/~}) — opcional, solo si algun flujo requiere credenciales"
fi

echo
echo "── Plane (seguimiento, opcional) ──"
plane_ws="$(swarm_ws_marker PLANE_WORKSPACE)"; plane_proj="$(swarm_ws_marker PLANE_PROJECT)"
if [ -z "$plane_ws" ] || [ -z "$plane_proj" ]; then
    warn "Plane no configurado (markers PLANE_WORKSPACE/PLANE_PROJECT en workspace.md) — opcional"
elif [ -z "${PLANE_API_KEY:-}" ]; then
    warn "Plane configurado ($plane_ws) pero sin PLANE_API_KEY en el archivo de secretos"
else
    plane_conx="$(bash "$NOKEY_CLAUDE_DIR/scripts/plane.sh" env 2>/dev/null | grep -i 'conexi')"
    case "$plane_conx" in
        *"HTTP 200"*) ok "Plane OK ($plane_ws) — conexion HTTP 200" ;;
        *)            warn "Plane configurado ($plane_ws) pero la conexion fallo: ${plane_conx:-sin respuesta}" ;;
    esac
fi

echo
echo "── Git (enjambre .claude/) ──"
if ! command -v git >/dev/null 2>&1; then
    warn "git no disponible"
elif ! git -C "$NOKEY_CLAUDE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    warn ".claude/ no es un repo git (no hay auto-update del enjambre)"
else
    ok "repo git (.claude/) detectado"
    git -C "$NOKEY_CLAUDE_DIR" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 \
        && ok "upstream configurado (auto-pull al iniciar)" \
        || warn "branch sin upstream: el SessionStart no podra actualizar el enjambre"
fi

echo
echo "DOCTOR: $OK_N ok, $WARN_N warn, $FAIL_N fail"
[ "$FAIL_N" -eq 0 ]
