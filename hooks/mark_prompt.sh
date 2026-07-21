#!/bin/bash
# Hook UserPromptSubmit para Claude Code: marca el inicio del turno (timestamp) para que
# on_stop.sh mida la duracion y notifique SOLO tareas largas. No escribe nada a stdout
# (en UserPromptSubmit el stdout se inyecta como contexto). Exit 0 siempre.

input=$(cat)
sid=$(printf '%s' "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id','') or '')" 2>/dev/null)
[ -n "$sid" ] || sid="default"

printf '%s' "$(date +%s)" > "${TMPDIR:-/tmp}/swarm_turn_${sid}" 2>/dev/null
exit 0
