#!/bin/bash
# scripts/git_state.sh — deteccion determinista de estado Git para @git-flow.
#
# Resuelve lo mecanico que el agente antes razonaba: toplevel, tipo de repo (trabajo/core/enjambre),
# rama actual (protegida o de trabajo), staged y modulos tocados. La convencion (naming de ramas,
# formato de commit) vive en el skill `git`; esto solo DETECTA. Read-only: no muta el repo.
#
# Uso:
#   git_state.sh state [path]   estado completo (default: cwd). Lineas KEY=value parseables.

set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/../hooks/lib.sh" 2>/dev/null || { echo "ERROR: no se pudo cargar hooks/lib.sh" >&2; exit 1; }

die() { echo "ERROR: $*" >&2; exit 1; }

cmd="${1:-state}"; path="${2:-$PWD}"
[ -e "$path" ] || die "no existe el path '$path'"

top="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)" || die "'$path' no esta dentro de un repo git"

# Clase de repo: los scripts/agentes solo operan sobre repos de TRABAJO.
repo_kind="work"
[ "$top" = "$NOKEY_CLAUDE_DIR" ] && repo_kind="enjambre"
swarm_is_core_path "$top/x" && repo_kind="core"

branch="$(git -C "$top" rev-parse --abbrev-ref HEAD 2>/dev/null)"

# Ramas protegidas (branch-first — nunca escribir directo ahi): main/master + las ramas largas
# de deploy declaradas en workspace.md (PROD_BRANCH/STAGING_BRANCH; en Odoo.sh un push a esas
# ramas deploya el entorno). feature/fix nacen de staging; hotfix nace de prod (ver skill `git`).
staging_branch="$(swarm_staging_branch)"
prod_branch="$(swarm_prod_branch)"
protected="no"
case "$branch" in
    main|master) protected="yes" ;;
esac
[ -n "$staging_branch" ] && [ "$branch" = "$staging_branch" ] && protected="yes"
[ -n "$prod_branch" ] && [ "$branch" = "$prod_branch" ] && protected="yes"

# Staged y modulos tocados (swarm_module_root sobre cada path staged, dedup).
staged="$(git -C "$top" diff --staged --name-only 2>/dev/null)"
n_staged="$(printf '%s' "$staged" | grep -c . || true)"
n_unstaged="$(git -C "$top" status --porcelain 2>/dev/null | grep -c .)"
modules=""
if [ -n "$staged" ]; then
    modules="$(printf '%s\n' "$staged" | while IFS= read -r f; do
        [ -n "$f" ] || continue
        m="$(swarm_module_root "$top/$f")"
        [ -n "$m" ] && basename "$m"
    done | awk '!seen[$0]++' | paste -sd, -)"
fi

case "$cmd" in

state)
    echo "REPO=$top"
    echo "REPO_KIND=$repo_kind"
    echo "BRANCH=$branch"
    echo "PROTECTED_BRANCH=$protected"
    echo "STAGING_BRANCH=${staging_branch:-}"
    echo "PROD_BRANCH=${prod_branch:-}"
    echo "DEPLOY_PLATFORM=$(swarm_deploy_platform)"
    echo "STAGED_COUNT=$n_staged"
    echo "CHANGES_COUNT=$n_unstaged"
    echo "MODULES_STAGED=${modules:-}"
    echo
    case "$repo_kind" in
        core)     echo "⛔ Repo core/enterprise: NO operar aca." ;;
        enjambre) echo "⛔ Repo del enjambre (.claude/): fuera de este flujo (lo gestiona session_pull.sh)." ;;
    esac
    if [ "$protected" = "yes" ]; then
        echo "⛔ Parado en rama protegida ($branch): crear una rama de trabajo ANTES de escribir (branch-first)."
        if [ -n "$staging_branch" ]; then
            echo "   feature/fix nacen de '$staging_branch' (staging); hotfix nace de '${prod_branch:-main}' (producción). Ver skill git."
        fi
    else
        echo "✓ Rama de trabajo ($branch)."
    fi
    [ -n "$staged" ] && { echo; echo "Staged:"; printf '%s\n' "$staged" | sed 's/^/  /'; }
    exit 0
    ;;

*)
    die "subcomando desconocido '$cmd' (uso: state [path])"
    ;;
esac
