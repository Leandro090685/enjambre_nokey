#!/bin/bash
# Hook PreToolUse para Claude Code: impide editar archivos de core/enterprise.
#
# Convencion del proyecto (AGENTS.md): NUNCA modificar odoo/ ni enterprise/ — heredar con
# _inherit. Este hook hace cumplir esa regla a nivel herramienta: si un Write/Edit/
# MultiEdit apunta a una raiz de core/enterprise (resueltas via lib.sh desde
# workspace.md), bloquea la operacion.
#
# Codigos de salida (contrato de Claude Code):
#   0  -> permitir (el archivo no es core/enterprise, o no se pudo determinar)
#   2  -> bloquear: stderr se devuelve a Claude para que corrija el enfoque

input=$(cat)

# Extraer file_path del JSON (tool_input.file_path). Usa python3 por portabilidad.
file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path','') or '')" 2>/dev/null)

# Sin file_path no hay nada que proteger: permitir.
[ -z "$file_path" ] && exit 0

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

if swarm_is_core_path "$file_path"; then
    printf '%s\n' "BLOQUEADO: '$file_path' esta bajo core/enterprise (CORE_ROOTS). Convencion del proyecto (AGENTS.md): NUNCA modificar odoo/ ni enterprise/. Heredá el modelo/vista con _inherit desde un modulo custom bajo ADDONS_ROOTS y llamá a super()." >&2
    exit 2
fi

exit 0
