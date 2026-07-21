#!/bin/bash
# Hook SubagentStop para Claude Code: cuando termina un SUBAGENTE (Task tool) — el flujo del
# orquestador SIGUE. Notifica el avance de etapa con datos reales: que agente termino y el
# Status/Resumen de su Result Envelope (estandar del enjambre, ver CLAUDE.md).
#
# Gate anti-ruido (decision del equipo): solo notifica si el turno ya lleva mas del umbral
# (NOKEY_NOTIFY_MIN_SECONDS, default 45s) — flujos cortos no pinguean. NO borra la marca de
# inicio (eso es del Stop). NOKEY_NOTIFY_SUBAGENTS=0 lo apaga. Exit 0 siempre.

[ "${NOKEY_NOTIFY_SUBAGENTS:-1}" = "0" ] && exit 0

input=$(cat)

# Parse en un solo pase: session_id, agent_type, Status y Resumen del envelope.
#   linea 1: session_id · 2: agent_type · 3: status · 4: resumen/snippet
parsed=$(printf '%s' "$input" | python3 -c "
import json, re, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get('session_id') or '')
print(d.get('agent_type') or d.get('subagent_type') or 'subagente')
msg = d.get('last_assistant_message') or ''
m = re.search(r'^\s*Status:\s*([A-Z_]+)', msg, re.MULTILINE)
print(m.group(1) if m else '')
m = re.search(r'^\s*Resumen:\s*(.+)$', msg, re.MULTILINE)
if m:
    s = m.group(1).strip()
else:
    # sin envelope: primera linea de PROSA del mensaje final (saltea headers/separadores)
    s = next((l.strip().lstrip('*- ').strip() for l in msg.splitlines()
              if l.strip() and not l.strip().startswith(('#', '---', '|', '>'))), '')
s = s.replace('\`', '').replace('**', '')
print(s[:120] + ('…' if len(s) > 120 else ''))
" 2>/dev/null)

sid=$(printf '%s' "$parsed" | sed -n '1p'); [ -n "$sid" ] || sid="default"
agent=$(printf '%s' "$parsed" | sed -n '2p')
status=$(printf '%s' "$parsed" | sed -n '3p')
resumen=$(printf '%s' "$parsed" | sed -n '4p')

# Gate por umbral: leer la marca del turno SIN borrarla.
mark="${TMPDIR:-/tmp}/swarm_turn_${sid}"
min="${NOKEY_NOTIFY_MIN_SECONDS:-45}"
[ -f "$mark" ] || exit 0
start=$(cat "$mark" 2>/dev/null)
case "$start" in ''|*[!0-9]*) exit 0 ;; esac
elapsed=$(( $(date +%s) - start ))
[ "$elapsed" -ge "$min" ] || exit 0

case "$status" in
    BLOCKED|NEEDS_INPUT|FAILED)
        title="⚠️ Subagente @${agent}: ${status} — Nokey" ;;
    *)
        title="🔁 Subagente @${agent} terminó — el flujo sigue" ;;
esac
body="${status:+Status: $status — }${resumen:-sin detalle}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$DIR/notify.sh" "$title" "$body" >/dev/null 2>&1
exit 0
