#!/bin/bash
# Hook Stop para Claude Code: cuando el agente PRINCIPAL (orquestador) termina su turno.
# Notificaciones diferenciadas:
#   - Si el turno quedo ESPERANDO una respuesta del usuario (el mensaje final termina en
#     pregunta) -> notifica SIEMPRE (sin umbral): es el caso donde no queres enterarte tarde.
#   - Si termino normal -> notifica solo si fue largo (elapsed >= NOKEY_NOTIFY_MIN_SECONDS,
#     default 45s), para no pinguear en cada mensaje del chat.
# El cuerpo incluye un extracto del mensaje final (que termino, concretamente).
# Usa la marca de inicio de mark_prompt.sh (y es el UNICO que la borra). Exit 0 siempre.

input=$(cat)

# Parse del input en un solo pase: session_id + clasificacion del mensaje final.
#   linea 1: session_id · linea 2: waiting yes/no · linea 3: snippet
parsed=$(printf '%s' "$input" | python3 -c "
import json, re, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get('session_id') or '')
msg = (d.get('last_assistant_message') or '').strip()
# ¿quedo esperando respuesta? -> el final del mensaje es una pregunta
tail = msg[-300:].rstrip().rstrip('*_\`')
last_line = tail.splitlines()[-1].strip() if tail else ''
waiting = bool(msg) and (tail.endswith('?') or bool(re.search(r'¿[^?]*\?', last_line)))
print('yes' if waiting else 'no')
# snippet: primera linea de PROSA (saltea headers #, separadores y envelope)
snippet = ''
for line in msg.splitlines():
    raw = line.strip()
    if not raw or raw.startswith(('#', '---', '|', '>')):
        continue
    s = raw.lstrip('*- ').strip()
    if not s or s.lower().startswith(('status:', 'resumen:', 'proximo', 'riesgos', 'skill resolution')):
        continue
    snippet = s
    break
if waiting and last_line:
    snippet = last_line.lstrip('#>*- ').strip()
snippet = snippet.replace('\`', '').replace('**', '')
print(snippet[:140] + ('…' if len(snippet) > 140 else ''))
" 2>/dev/null)

sid=$(printf '%s' "$parsed" | sed -n '1p'); [ -n "$sid" ] || sid="default"
waiting=$(printf '%s' "$parsed" | sed -n '2p')
snippet=$(printf '%s' "$parsed" | sed -n '3p')

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mark="${TMPDIR:-/tmp}/swarm_turn_${sid}"
min="${NOKEY_NOTIFY_MIN_SECONDS:-45}"

# elapsed desde la marca de inicio (si no hay marca: sesion resumida / primer arranque)
elapsed=""
if [ -f "$mark" ]; then
    start=$(cat "$mark" 2>/dev/null)
    rm -f "$mark" 2>/dev/null
    case "$start" in ''|*[!0-9]*) : ;; *) elapsed=$(( $(date +%s) - start )) ;; esac
fi

if [ "$waiting" = "yes" ]; then
    # Quedo esperando al usuario -> avisar SIEMPRE (aunque el turno haya sido corto)
    bash "$DIR/notify.sh" "⌛ Esperando tu respuesta — Nokey" "${snippet:-El flujo quedo esperando una decision tuya}" >/dev/null 2>&1
elif [ -n "$elapsed" ] && [ "$elapsed" -ge "$min" ]; then
    bash "$DIR/notify.sh" "✅ Turno completo (${elapsed}s) — Nokey" "${snippet:-Tarea lista}" >/dev/null 2>&1
fi
exit 0
