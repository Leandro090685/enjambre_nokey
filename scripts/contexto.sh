#!/bin/bash
# scripts/contexto.sh — dashboard de orientacion on-demand para el comando /contexto.
# Backend del comando: junta el contexto del workspace (entorno, git, clientes, modulo actual)
# reutilizando los helpers de hooks/lib.sh. Read-only, best-effort. Salida en texto plano.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/../hooks/lib.sh" 2>/dev/null || { echo "No se pudo cargar hooks/lib.sh"; exit 1; }

root="$(swarm_workspace_root)"
ver="$(swarm_ws_marker ODOO_VERSION)"; [ -n "$ver" ] || ver="(no declarada)"
container="$(swarm_ws_marker ODOO_CONTAINER)"
db="$(swarm_ws_marker ODOO_DB_CONTAINER)"
engine="$(swarm_container_engine)"
docker="$(swarm_docker_status)"

echo "=== CONTEXTO DEL WORKSPACE ==="
echo
echo "── Entorno ──"
echo "  Odoo version : $ver"
if [ -n "$container" ]; then
    echo "  Contenedor   : $container [$docker] ($engine)"
else
    echo "  Contenedor   : (sin marcador ODOO_CONTAINER en workspace.md)"
fi
[ -n "$db" ] && echo "  Docker DB    : $db"
echo "  Workspace    : $root"

echo
echo "── Git (enjambre .claude/) ──"
enj="$NOKEY_CLAUDE_DIR"
branch="$(git -C "$enj" rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [ -n "$branch" ]; then
    n_changes="$(git -C "$enj" status --porcelain 2>/dev/null | grep -c .)"
    if [ "$n_changes" -eq 0 ] 2>/dev/null; then
        echo "  Branch       : $branch (limpio)"
    else
        echo "  Branch       : $branch ($n_changes cambios sin commitear)"
    fi
    echo "  Ultimos commits:"
    git -C "$enj" log --oneline -3 2>/dev/null | sed 's/^/    /'
else
    echo "  (no es un repo git o git no disponible)"
fi

echo
echo "── Workspace ──"
clients="$(swarm_client_addons | while IFS= read -r p; do [ -n "$p" ] && basename "$p"; done | paste -sd, - 2>/dev/null | sed 's/,/, /g')"
products="$(swarm_product_addons | grep -c .)"
echo "  Clientes     : ${clients:-(ninguno declarado)}"
echo "  Productos    : ${products:-0} repos compartidos"
echo "  Modulos      : $(swarm_module_count) (carpetas con __manifest__.py)"

echo
echo "── Donde estoy (cwd) ──"
mod="$(swarm_module_root "$PWD/probe" 2>/dev/null)"
if [ -n "$mod" ]; then
    mname="$(basename "$mod")"
    mver="$(swarm_manifest_version "$mod")"
    echo "  Modulo       : $mname"
    echo "  version      : ${mver:-(no legible)}"
    spec="$(swarm_module_spec "$mod")"
    if [ -n "$spec" ]; then
        sver="$(swarm_spec_version "$spec")"
        echo "  SDD          : si (spec ${spec#"$root"/})"
        echo "  spec Version : ${sver:-(no legible)}"
        if [ -n "$mver" ] && [ -n "$sver" ] && [ "$mver" != "$sver" ]; then
            echo "  ⚠ DRIFT      : manifest ($mver) != spec ($sver) — sincronizar"
        fi
    else
        echo "  SDD          : no (modulo sin specs/)"
    fi
else
    echo "  (el directorio actual no esta dentro de un modulo Odoo)"
fi
