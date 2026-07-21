#!/bin/bash
# Hook Notification para Claude Code: dispara cuando Claude pide permiso o queda esperando
# input del usuario. Clasifica por el campo `type` del evento para que el titulo diga QUE
# esta pasando (permiso vs input), en vez de un generico. Exit 0 siempre.

input=$(cat)

#   linea 1: type · linea 2: message
parsed=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get('type') or '')
print((d.get('message') or '').replace('\n', ' ').strip())
" 2>/dev/null)

ntype=$(printf '%s' "$parsed" | sed -n '1p')
msg=$(printf '%s' "$parsed" | sed -n '2p')
[ -n "$msg" ] || msg="Claude Code necesita tu atencion"

case "$ntype" in
    permission_prompt)              title="🔐 Permiso requerido — Nokey" ;;
    idle_prompt|agent_needs_input)  title="⏸ Esperando tu input — Nokey" ;;
    *)                              title="Claude Code — Nokey" ;;
esac

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$DIR/notify.sh" "$title" "$msg" >/dev/null 2>&1
exit 0
