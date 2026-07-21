#!/bin/bash
# scripts/cliente.sh — inventario determinista de un repo de cliente para @client-context.
#
# Emite, por modulo: version del manifest, summary, depends, si es SDD (spec + Estado + Version +
# drift vs manifest), docs presentes (README/index.html), tests presentes (backend y e2e, segun la
# politica .swarm.conf del repo) e integraciones detectadas por grep.
# El agente lo invoca y solo SINTETIZA (leer specs/READMEs puntuales donde haga falta).
# Read-only, best-effort.
#
# Uso:
#   cliente.sh                  lista los clientes declarados en CLIENT_ADDONS
#   cliente.sh <cliente|path>   inventario del cliente (match por nombre, case-insensitive) o de
#                               cualquier path de repo de addons (tambien sirve para PRODUCT_ADDONS)

set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/../hooks/lib.sh" 2>/dev/null || { echo "ERROR: no se pudo cargar hooks/lib.sh" >&2; exit 1; }

# Estado declarado en la spec (fila "| **Estado** | `xxx` |"). Solo la primera palabra
# (la celda suele arrastrar notas largas entre parentesis). Vacio si no hay.
spec_state() {
    grep -iE '^\|[[:space:]]*\*\*Estado\*\*[[:space:]]*\|' "$1" 2>/dev/null \
        | head -1 | sed -E 's/^\|[^|]*\|[[:space:]]*//; s/`//g; s/^\*+//; s/[^a-zA-Z_].*$//'
}

target="${1:-}"

if [ -z "$target" ]; then
    echo "Clientes declarados (CLIENT_ADDONS en workspace.md):"
    swarm_client_addons | while IFS= read -r p; do
        [ -n "$p" ] || continue
        n="$(find "$p" -maxdepth 2 -name __manifest__.py 2>/dev/null | wc -l | tr -d ' ')"
        echo "  $(basename "$p")  ($n modulos)  $p"
    done
    exit 0
fi

# Resolver el path del cliente: path directo, o match case-insensitive contra CLIENT_ADDONS.
repo=""
if [ -d "$target" ]; then
    repo="$(cd "$target" && pwd)"
else
    tl="$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')"
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        case "$(basename "$p" | tr '[:upper:]' '[:lower:]')" in
            *"$tl"*) repo="$p"; break ;;
        esac
    done < <(swarm_client_addons)
fi
[ -n "$repo" ] && [ -d "$repo" ] || { echo "ERROR: no encontre el cliente '$target' (ni como path ni en CLIENT_ADDONS)" >&2; exit 1; }

echo "=== INVENTARIO: $(basename "$repo") ==="
echo "Path: $repo"
branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ -n "$branch" ] && echo "Rama git: $branch"
if [ -f "$repo/README.md" ]; then echo "README raiz del repo: si"; else echo "README raiz del repo: NO (falta indice de modulos)"; fi
tests_policy="$(swarm_repo_conf TESTS "$repo")"
e2e_policy="$(swarm_repo_conf E2E "$repo")"
pol=""
[ "$tests_policy" = "required" ] && pol="backend"
[ "$e2e_policy" = "required" ] && pol="${pol:+$pol + }e2e (UI/tours)"
if [ -n "$pol" ]; then
    echo "Politica de tests (.swarm.conf): REQUERIDOS -> $pol"
else
    echo "Politica de tests (.swarm.conf): no declarada (tests no requeridos)"
fi
echo

mods=0; sdd=0; drift=0
while IFS= read -r mf; do
    mod="$(dirname "$mf")"; name="$(basename "$mod")"
    mods=$((mods+1))
    mver="$(swarm_manifest_version "$mod")"

    # summary y depends desde el manifest (ast; best-effort; separados por TAB)
    IFS=$'\t' read -r summary depends < <(python3 - "$mf" <<'PY' 2>/dev/null
import ast, sys
try:
    d = ast.literal_eval(open(sys.argv[1], encoding="utf-8").read())
    s = " ".join((d.get("summary") or "").split()) or "-"
    dep = ",".join(d.get("depends") or []) or "-"
    print(s + "\t" + dep)
except Exception:
    print("-\t-")
PY
)

    echo "── $name ──"
    echo "  version  : ${mver:-(no legible)}"
    echo "  summary  : ${summary:--}"
    echo "  depends  : ${depends:--}"

    spec="$(swarm_module_spec "$mod")"
    if [ -n "$spec" ]; then
        sdd=$((sdd+1))
        sver="$(swarm_spec_version "$spec")"
        sstate="$(spec_state "$spec")"
        line="  SDD      : si — ${spec#"$repo"/} · estado ${sstate:-?} · Version ${sver:-?}"
        if [ -n "$mver" ] && [ -n "$sver" ] && [ "$mver" != "$sver" ]; then
            line="$line ≠ manifest ($mver) ⚠ DRIFT"
            drift=$((drift+1))
        elif [ -n "$sver" ]; then
            line="$line == manifest ✓"
        fi
        echo "$line"
    else
        echo "  SDD      : no"
    fi

    docs=""
    [ -f "$mod/README.md" ] || docs="README.md"
    [ -f "$mod/static/description/index.html" ] || docs="${docs:+$docs + }index.html"
    if [ -n "$docs" ]; then echo "  docs     : FALTA $docs"; else echo "  docs     : ok"; fi

    if swarm_module_has_tests "$mod"; then
        echo "  tests    : si"
    elif [ "$tests_policy" = "required" ]; then
        echo "  tests    : NO ⚠ (el repo los requiere — agregar al tocar el modulo)"
    else
        echo "  tests    : no"
    fi

    if swarm_module_has_e2e "$mod"; then
        echo "  e2e      : si (tour)"
    elif [ "$e2e_policy" = "required" ] && swarm_module_has_ui "$mod"; then
        echo "  e2e      : NO ⚠ (repo requiere e2e y hay superficie de UI — tour si el flujo es troncal)"
    elif [ "$e2e_policy" = "required" ]; then
        echo "  e2e      : n/a (backend puro)"
    fi

    # integraciones por grep (senales, no certezas): HTTP salientes, webhooks/controllers
    integ=""
    grep -rlqE 'import requests|http\.client|urllib\.request|xmlrpc' "$mod" --include="*.py" 2>/dev/null \
        && integ="HTTP saliente"
    [ -d "$mod/controllers" ] && integ="${integ:+$integ, }controllers/endpoints"
    [ -n "$integ" ] && echo "  integr.  : $integ"
    echo
done < <(find "$repo" -maxdepth 2 -name __manifest__.py 2>/dev/null | sort)

echo "=== RESUMEN ==="
echo "Modulos: $mods · SDD: $sdd · con drift de version: $drift"
[ "$drift" -gt 0 ] && echo "⚠ Hay specs desincronizadas del manifest — reportar como hallazgo."
exit 0
