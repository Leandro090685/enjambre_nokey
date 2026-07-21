#!/bin/bash
# Hook SessionStart para Claude Code: imprime un banner de ORIENTACION al arrancar
# (version de Odoo, clientes, branch, estado de Docker, # de modulos), para que el
# desarrollador se ubique de un vistazo y Claude arranque orientado.
#
# Complementa a session_pull.sh (que actualiza el repo del enjambre): este NO toca git,
# solo informa. Best-effort: nunca bloquea ni rompe el arranque. Exit 0 siempre.
#
# Claude Code entrega el payload por stdin (JSON con 'source': startup|resume|clear|compact).
# Salida: JSON con systemMessage (lo ve el dev) + hookSpecificOutput.additionalContext (lo ve Claude).

input=$(cat)

# En 'compact' no orientamos: es continuacion de la misma sesion (mismo contexto).
source=$(printf '%s' "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('source','') or '')" 2>/dev/null)
case "$source" in compact) exit 0 ;; esac

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/lib.sh" 2>/dev/null || exit 0

line="$(swarm_orientation_line 2>/dev/null)"
[ -n "$line" ] || exit 0

python3 - "$line" <<'PY'
import json, sys
note = "Orientacion: " + sys.argv[1]
print(json.dumps({
    "systemMessage": "[enjambre] " + note,
    "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": note},
}))
PY
exit 0
