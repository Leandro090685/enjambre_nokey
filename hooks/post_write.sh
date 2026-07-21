#!/bin/bash
# Hook PostToolUse para Claude Code: puente entre el evento Write/Edit y las
# validaciones del proyecto.
#
# Claude Code entrega el payload del hook como JSON por stdin. Extraemos el
# file_path, filtramos .py/.xml y ejecutamos los dos validadores en secuencia.
#
# Codigos de salida (contrato de Claude Code):
#   0  -> sin problemas (los warnings se informan por stdout)
#   2  -> bloqueante: stderr se devuelve a Claude para que corrija
#         (se usa solo para breaking changes de la version objetivo, que deben corregirse)

input=$(cat)

# Extraer file_path del JSON (tool_input.file_path). Usa python3 por portabilidad.
file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path','') or '')" 2>/dev/null)

[ -z "$file_path" ] && exit 0

case "$file_path" in
    *.py|*.xml) ;;
    *) exit 0 ;;
esac

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

# Hook 1: convenciones del proyecto (headers, modelines, sintaxis, manifest, docs).
# Informativo: sus warnings no bloquean. Capturamos la salida para mostrarsela al usuario.
validator_output=$(bash "$DIR/validate_files.sh" "$file_path")

# Hook 2: breaking changes de la version objetivo. Si detecta patrones prohibidos, bloquea
# devolviendo el detalle a Claude por stderr (exit 2).
bc_output=$(bash "$DIR/check_breaking_changes.sh" "$file_path")
bc_status=$?
if [ $bc_status -ne 0 ]; then
    printf '%s\n' "$bc_output" >&2
    exit 2
fi

# --- Documentacion del modulo (recordatorio al AGENTE via additionalContext, no bloqueante) ---
# Los warnings de validate_files.sh solo los ve el usuario; additionalContext SI llega al agente.
doc_note=""
module_dir=$(swarm_module_root "$file_path")
if [ -n "$module_dir" ]; then
    has_readme=0; has_index=0
    [ -f "$module_dir/README.md" ] && has_readme=1
    [ -f "$module_dir/static/description/index.html" ] && has_index=1
    if [ $has_readme -eq 0 ] && [ $has_index -eq 0 ]; then
        doc_note="DOCUMENTACION FALTANTE en el modulo '$module_dir': no tiene README.md ni static/description/index.html. Regla obligatoria del proyecto: genera la documentacion (procedimiento @module-index-html) antes de dar por terminada la tarea. No omitas este paso aunque el cambio sea chico (ej. un string o un fix puntual)."
    elif [ $has_readme -eq 0 ] || [ $has_index -eq 0 ]; then
        if [ $has_readme -eq 0 ]; then falta="README.md"; else falta="static/description/index.html"; fi
        doc_note="DOCUMENTACION INCOMPLETA en el modulo '$module_dir': falta $falta. Completala (procedimiento @module-index-html) antes de cerrar la tarea."
    else
        doc_note="El modulo '$module_dir' ya tiene documentacion. Si este cambio altera funcionalidad visible, actualiza README.md y static/description/index.html en consecuencia."
    fi
fi

# --- Spec SDD: el modulo es gestionado por SDD si tiene specs/ (no bloqueante) ---
# Recordamos: spec = fuente de verdad, update en sitio (no acumulativo), version spec == manifest.
spec_note=""
if [ -n "$module_dir" ]; then
    spec_file=$(swarm_module_spec "$module_dir")
    # Si se acaba de tocar la propia spec, no hace falta recordar nada.
    case "$file_path" in */specs/*.md) spec_file="" ;; esac
    if [ -n "$spec_file" ]; then
        spec_ver=$(swarm_spec_version "$spec_file")
        manifest_ver=$(swarm_manifest_version "$module_dir")
        spec_rel="${spec_file#"$module_dir"/}"
        if [ -n "$spec_ver" ] && [ -n "$manifest_ver" ] && [ "$spec_ver" != "$manifest_ver" ]; then
            spec_note="MODULO SDD con DRIFT DE VERSION en '$module_dir': la spec '$spec_rel' esta en Version $spec_ver pero el __manifest__.py esta en $manifest_ver. La spec es la fuente de verdad del modulo: reflejá este cambio EN SITIO en la spec (no acumular changelog) y dejá la 'Version' de la spec IGUAL al 'version' del manifest (formato x.x.x). Si el cambio contradice la spec, NO sigas: avisá al usuario antes de continuar."
        else
            spec_note="MODULO SDD en '$module_dir' (spec '$spec_rel' = fuente de verdad). Antes de cerrar la tarea: 1) si este cambio contradice la spec, avisá al usuario ANTES de continuar; 2) reflejá el cambio EN SITIO en la spec (no acumular changelog); 3) bumpeá 'version' del manifest (x.x.x) y dejá la 'Version' de la spec igual."
        fi
    fi
fi

# --- Politica de tests del repo (.swarm.conf TESTS=required, no bloqueante) ---
# Solo aplica si el repo declara la politica; sin .swarm.conf no se menciona nada.
tests_note=""
if [ -n "$module_dir" ] && swarm_tests_required "$file_path"; then
    if swarm_module_has_tests "$module_dir"; then
        tests_note="Este repo requiere tests (.swarm.conf TESTS=required) y el modulo '$module_dir' ya tiene suite. Si este cambio agrega o modifica un flujo troncal, actualiza/agrega los tests de ese flujo (skill odoo-tests) y corre la suite del modulo (odoo_runtime.sh test) antes de cerrar la tarea. Cambios menores (un string, un label) no exigen tests."
    else
        tests_note="TESTS FALTANTES en el modulo '$module_dir': este repositorio requiere tests (.swarm.conf TESTS=required) y el modulo no tiene tests/ con test_*.py. Antes de dar la tarea por terminada: agrega tests de los flujos troncales del modulo (sin exagerar — happy paths + constraints clave, ver skill odoo-tests) y correlos (odoo_runtime.sh test / @testing)."
    fi
fi

# --- Politica de tests e2e del repo (.swarm.conf E2E=required, no bloqueante) ---
# Eje INDEPENDIENTE de TESTS. Alcance por juicio: solo modulos con superficie de UI; un backend
# puro no dispara nada (evita el falso "falta e2e"). Los tours necesitan Chrome en el contenedor.
e2e_note=""
if [ -n "$module_dir" ] && swarm_e2e_required "$file_path"; then
    if swarm_module_has_e2e "$module_dir"; then
        e2e_note="Este repo requiere e2e (.swarm.conf E2E=required) y el modulo '$module_dir' ya tiene un tour. Si este cambio toca el flujo de UI cubierto, actualiza/ajusta el tour (HttpCase.start_tour, skill odoo-tests) y correlo de verdad: @testing asegura Chrome primero (si falta, pregunta e instala) — un tour que queda SKIPPED no cuenta como pasado."
    elif swarm_module_has_ui "$module_dir"; then
        e2e_note="Este repo requiere e2e (.swarm.conf E2E=required) y el modulo '$module_dir' tiene superficie de UI (controllers/JS) sin tour. Si este cambio toca un flujo de UI troncal, agrega un test e2e (Tour de Odoo: JS en static/src registrado en web_tour.tours + HttpCase.start_tour, ver skill odoo-tests) y correlo de verdad: @testing asegura Chrome antes (si falta, pregunta e instala) — un tour SKIPPED no cuenta como pasado. Si el cambio no toca UI, no aplica."
    fi
fi

# --- Indice del repositorio: README.md raiz del repo de addons (no bloqueante) ---
repo_note=""
repo_root=$(swarm_repo_root "$file_path")
if [ -n "$repo_root" ] && [ -d "$repo_root" ] && [ ! -f "$repo_root/README.md" ]; then
    repo_note="INDICE DE REPOSITORIO FALTANTE en '$repo_root': no tiene README.md raiz (indice de modulos). Regla del proyecto: cada repo de addons custom lleva un README.md con el indice de sus modulos. Genera/actualiza el indice (procedimiento @module-index-html) antes de cerrar la tarea."
fi

# Armar additionalContext (para el agente): info de breaking-changes + recordatorio de docs.
ctx=""
[ -n "$bc_output" ] && ctx="$bc_output"
if [ -n "$doc_note" ]; then
    [ -n "$ctx" ] && ctx="$ctx
"
    ctx="$ctx$doc_note"
fi
if [ -n "$spec_note" ]; then
    [ -n "$ctx" ] && ctx="$ctx
"
    ctx="$ctx$spec_note"
fi
if [ -n "$tests_note" ]; then
    [ -n "$ctx" ] && ctx="$ctx
"
    ctx="$ctx$tests_note"
fi
if [ -n "$e2e_note" ]; then
    [ -n "$ctx" ] && ctx="$ctx
"
    ctx="$ctx$e2e_note"
fi
if [ -n "$repo_note" ]; then
    [ -n "$ctx" ] && ctx="$ctx
"
    ctx="$ctx$repo_note"
fi

# Sin nada que inyectarle al agente: salida normal (texto plano al usuario).
if [ -z "$ctx" ]; then
    printf '%s\n' "$validator_output"
    exit 0
fi

# Emitir JSON: additionalContext -> agente (no bloqueante); systemMessage -> usuario.
python3 - "$validator_output" "$ctx" <<'PY'
import json, sys
validator = sys.argv[1]
ctx = sys.argv[2]
out = {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": ctx}}
if validator.strip():
    out["systemMessage"] = validator
print(json.dumps(out))
PY
exit 0
