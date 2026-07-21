#!/bin/bash
# Hook SessionStart para Claude Code: mantiene el repo del enjambre (.claude/)
# actualizado con un pull SEGURO al arrancar la sesion, antes de procesar el prompt.
#
# Principios:
#   - NUNCA bloquea ni rompe trabajo local. El fetch es read-only; el pull es
#     SOLO fast-forward y SOLO con el arbol de trabajo limpio.
#   - Si hay cambios locales sin commitear, divergencia, o no hay red/auth, NO
#     toca nada: solo informa el estado por additionalContext.
#   - Sin prompts interactivos (BatchMode) y con timeout, para no colgar la sesion.
#
# Claude Code entrega el payload por stdin (JSON con 'source': startup|resume|clear|compact).
# Salida: JSON con hookSpecificOutput.additionalContext (lo ve el agente). Exit 0 siempre.

input=$(cat)

# Fuente del evento. En 'compact' no tiene sentido pullear (es continuacion de la misma sesion).
source=$(printf '%s' "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('source','') or '')" 2>/dev/null)
case "$source" in compact) exit 0 ;; esac

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"   # raiz del repo del enjambre (.claude/)

# Emite el estado: additionalContext (al agente) + systemMessage (visible al usuario) y termina.
emit() {
    python3 - "$1" <<'PY'
import json, sys
note = sys.argv[1]
print(json.dumps({
    "systemMessage": "[enjambre] " + note,
    "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": note},
}))
PY
    exit 0
}

# Requisitos minimos: git disponible y .claude/ es un repo.
command -v git >/dev/null 2>&1 || exit 0
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Sin prompts interactivos; timeouts para no colgar el arranque.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5"

branch=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)

# Sin upstream configurado no hay con que comparar.
if ! git -C "$REPO" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    emit "Enjambre: la branch '$branch' no tiene upstream configurado; no se intento actualizar."
fi

# Fetch (read-only). Si falla -> offline o sin auth SSH: trabajamos con lo local.
if ! timeout 15 git -C "$REPO" fetch --quiet origin "$branch" 2>/dev/null; then
    emit "Enjambre: no se pudo contactar origin (offline o sin auth SSH). Trabajando con la version local de los agentes/skills/hooks."
fi

local_rev=$(git -C "$REPO" rev-parse @ 2>/dev/null)
remote_rev=$(git -C "$REPO" rev-parse '@{u}' 2>/dev/null)
base_rev=$(git -C "$REPO" merge-base @ '@{u}' 2>/dev/null)

if [ "$local_rev" = "$remote_rev" ]; then
    emit "Enjambre actualizado (origin/$branch @ ${local_rev:0:7})."

elif [ "$local_rev" = "$base_rev" ]; then
    # Estamos DETRAS de origin -> candidato a fast-forward.
    count=$(git -C "$REPO" rev-list --count '@..@{u}' 2>/dev/null)
    if [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]; then
        emit "Enjambre DESACTUALIZADO: $count commit(s) nuevos en origin/$branch, pero hay cambios locales sin commitear -> NO se hizo pull para no pisarlos. Comiteá/stasheá y corré: git -C \"$REPO\" pull --ff-only"
    fi
    if timeout 15 git -C "$REPO" merge --ff-only --quiet '@{u}' 2>/dev/null; then
        new_rev=$(git -C "$REPO" rev-parse @ 2>/dev/null)
        emit "Enjambre ACTUALIZADO por pull (ff-only): origin/$branch @ ${new_rev:0:7} ($count commit(s) traidos). Agentes/skills/hooks ya usan la version nueva en esta sesion; si cambio CLAUDE.md, abri una sesion nueva para tomarlo completo."
    else
        emit "Enjambre detras de origin/$branch ($count commit(s)) pero no se pudo fast-forward. Revisá manualmente: git -C \"$REPO\" status"
    fi

elif [ "$remote_rev" = "$base_rev" ]; then
    emit "Enjambre: tenés commits locales por delante de origin/$branch (nada que pullear). No olvides pushear si corresponde."

else
    emit "Enjambre: divergencia con origin/$branch (local y remoto avanzaron por separado). No se tocó nada; resolvé manualmente."
fi
