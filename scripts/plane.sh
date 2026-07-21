#!/bin/bash
# scripts/plane.sh — entrypoint de seguimiento en Plane.so para el enjambre.
#
# Resuelve la config desde workspace.md (markers PLANE_WORKSPACE, PLANE_PROJECT,
# PLANE_API_BASE) y la API key desde el archivo de secretos (NOKEY_SECRETS_FILE,
# formato KEY=value) via hooks/lib.sh, y delega en plane_api.py. NUNCA hardcodea la
# key ni el proyecto: si falta config, plane_api.py sale con un error claro.
#
# Uso: plane.sh <subcomando> [args]
#   env                              config resuelta + test de conexión
#   states | labels | members        catálogos del proyecto
#   list [--state N] [--priority P] [--search TXT]
#   get <#seq|uuid>
#   create --name "..." [--desc "..."] [--state N] [--priority P] [--label L]...
#   update <#seq|uuid> [--name ..] [--desc ..] [--state ..] [--priority ..] [--label ..]
#   move <#seq|uuid> "<Estado>"      atajo para cambiar el estado
#   comment <#seq|uuid> "texto"
#   delete <#seq|uuid> --yes         (destructivo)
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/../hooks/lib.sh" 2>/dev/null || { echo "ERROR: no se pudo cargar hooks/lib.sh" >&2; exit 1; }

# API key (y demás secretos) desde el archivo de secretos, sin pisar env ya seteado.
swarm_load_secrets

# Config no-secreta desde workspace.md; env override gana. API base con default.
export PLANE_API_BASE="${PLANE_API_BASE:-$(swarm_ws_marker PLANE_API_BASE)}"
[ -n "$PLANE_API_BASE" ] || export PLANE_API_BASE="https://api.plane.so/api/v1"
export PLANE_WORKSPACE="${PLANE_WORKSPACE:-$(swarm_ws_marker PLANE_WORKSPACE)}"
export PLANE_PROJECT="${PLANE_PROJECT:-$(swarm_ws_marker PLANE_PROJECT)}"
export PLANE_API_KEY="${PLANE_API_KEY:-}"

exec python3 "$DIR/plane_api.py" "$@"
