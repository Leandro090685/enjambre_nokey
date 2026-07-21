#!/bin/bash
# scripts/review_static.sh — pre-pass estatico de review sobre un MODULO completo.
#
# Corre on-demand lo mecanico del checklist de @reviewer: convenciones del proyecto
# (validate_files.sh), breaking changes por version (check_breaking_changes.sh) y greps
# extra del checklist (sudo, SQL sin sanitizar, ACLs faltantes, _description, convencion
# de XML IDs, __init__ incompleto, artefactos commiteados, cr.commit, print, politica de
# tests del repo via .swarm.conf). El REVIEWER
# (opus) consume este reporte y se queda solo con el juicio semantico — el orquestador lo
# corre y lo inyecta en el handoff (@reviewer no tiene Bash a proposito).
#
# Si el modulo es SDD, correr ADEMAS spec_lint.py (validacion de la spec).
# Read-only. Exit 0 siempre (es un reporte, no un gate — el gate es el hook al escribir).
#
# Uso: review_static.sh <modulo_path>

set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$DIR/../hooks"
# shellcheck source=/dev/null
. "$HOOKS/lib.sh" 2>/dev/null || { echo "ERROR: no se pudo cargar hooks/lib.sh" >&2; exit 1; }

mod="${1:-}"
[ -n "$mod" ] && [ -d "$mod" ] && [ -f "$mod/__manifest__.py" ] \
    || { echo "uso: review_static.sh <modulo_path>  (carpeta con __manifest__.py)" >&2; exit 1; }
mod="$(cd "$mod" && pwd)"
name="$(basename "$mod")"

echo "=== REVIEW ESTATICO: $name ==="
echo "Path: $mod"
echo

# Archivos del modulo (sin __pycache__)
py_files="$(find "$mod" -name "*.py" -not -path "*/__pycache__/*" 2>/dev/null | sort)"
xml_files="$(find "$mod" -name "*.xml" 2>/dev/null | sort)"

# ── 1. Convenciones del proyecto (hook validate_files.sh, on-demand sobre todo el modulo) ──
echo "── Convenciones del proyecto (validate_files.sh) ──"
# shellcheck disable=SC2086
out="$(bash "$HOOKS/validate_files.sh" $py_files $xml_files 2>&1)"
if [ -n "$out" ]; then echo "$out"; else echo "OK (sin observaciones)"; fi
echo

# ── 2. Breaking changes por version (hook check_breaking_changes.sh) ──
echo "── Breaking changes (check_breaking_changes.sh) ──"
# shellcheck disable=SC2086
out="$(bash "$HOOKS/check_breaking_changes.sh" $py_files $xml_files 2>&1)"
if [ -n "$out" ]; then echo "$out"; else echo "OK (sin patrones prohibidos)"; fi
echo

# ── 3. Greps del checklist (señales para el reviewer, no veredictos) ──
echo "── Señales de checklist (revisar con juicio) ──"

section() { echo; echo "· $1"; }

section "sudo() — cada uso requiere justificacion:"
grep -rn "\.sudo()" "$mod" --include="*.py" 2>/dev/null | grep -v "^Binary" | sed 's/^/  /' || echo "  (ninguno)"

section "SQL crudo con interpolacion (riesgo de injection; revisar parametrizacion):"
grep -rnE "cr\.execute\(.*(%s*\"|%\s*\(|\.format\(|f\"|f')" "$mod" --include="*.py" 2>/dev/null | sed 's/^/  /' || echo "  (ninguno)"

section "cr.commit() — prohibido salvo justificacion comentada:"
grep -rn "cr\.commit()" "$mod" --include="*.py" 2>/dev/null | sed 's/^/  /' || echo "  (ninguno)"

section "print() en codigo (usar _logger):"
grep -rnE "^\s*print\(" "$mod" --include="*.py" 2>/dev/null | grep -v "/tests/" | sed 's/^/  /' || echo "  (ninguno)"

section "Modelos sin _description:"
python3 - "$mod" <<'PY' 2>/dev/null || echo "  (no se pudo analizar)"
import re, sys
from pathlib import Path
found = False
for f in Path(sys.argv[1]).rglob("*.py"):
    if "__pycache__" in str(f):
        continue
    src = f.read_text(encoding="utf-8", errors="replace")
    # clases con _name propio (modelo nuevo) sin _description en el cuerpo
    for m in re.finditer(r"class\s+\w+\([^)]*models\.(?:Transient|Abstract)?Model[^)]*\):", src):
        body = src[m.end():]
        nxt = re.search(r"\nclass\s", body)
        body = body[:nxt.start()] if nxt else body
        has_name = re.search(r"_name\s*=", body)
        if has_name and not re.search(r"_description\s*=", body):
            line = src[:m.start()].count("\n") + 1
            print(f"  {f}:{line} — modelo con _name sin _description")
            found = True
if not found:
    print("  (ninguno)")
PY

section "ACLs — modelos nuevos sin fila en ir.model.access.csv:"
python3 - "$mod" <<'PY' 2>/dev/null || echo "  (no se pudo analizar)"
import re, sys
from pathlib import Path
mod = Path(sys.argv[1])
models = set()
for f in mod.rglob("*.py"):
    if "__pycache__" in str(f):
        continue
    src = f.read_text(encoding="utf-8", errors="replace")
    # _name propio (modelo/transient nuevo) declarado a inicio de linea (evita comodel_name=);
    # ignorar _name == _inherit (extension)
    for m in re.finditer(r"^\s*_name\s*=\s*[\"']([\w.]+)[\"']", src, re.MULTILINE):
        models.add(m.group(1))
    for m in re.finditer(r"^\s*_inherit\s*=\s*[\"']([\w.]+)[\"']", src, re.MULTILINE):
        models.discard(m.group(1))
acl = mod / "security" / "ir.model.access.csv"
acl_txt = acl.read_text(encoding="utf-8", errors="replace") if acl.is_file() else ""
missing = sorted(m for m in models if ("model_" + m.replace(".", "_")) not in acl_txt)
if not models:
    print("  (el modulo no define modelos nuevos)")
elif not acl_txt:
    print(f"  ⚠ {len(models)} modelo(s) nuevo(s) y NO existe security/ir.model.access.csv: " + ", ".join(sorted(models)))
elif missing:
    print("  ⚠ sin ACL: " + ", ".join(missing))
else:
    print(f"  OK ({len(models)} modelos con ACL)")
PY

section "Convencion de XML IDs de vistas ({model}_view_{tipo}) — solo vistas PROPIAS:"
python3 - "$mod" <<'PY' 2>/dev/null || echo "  (no se pudo analizar)"
import re, sys
from pathlib import Path
bad = []
for f in Path(sys.argv[1]).rglob("*.xml"):
    src = f.read_text(encoding="utf-8", errors="replace")
    for m in re.finditer(r'<record\s+id="([^"]+)"\s+model="ir.ui.view"', src):
        xid = m.group(1)
        # vistas heredadas reusan el XML ID de la original (convencion del proyecto): excluirlas
        body = src[m.end():]
        nxt = re.search(r"</record>", body)
        body = body[:nxt.start()] if nxt else body
        if "inherit_id" in body:
            continue
        if "_view_" not in xid and not xid.startswith("view_"):
            line = src[:m.start()].count("\n") + 1
            bad.append(f"  {f}:{line} — id '{xid}' no sigue {{model}}_view_{{tipo}}")
print("\n".join(bad) if bad else "  (ok)")
PY

section "__init__.py — archivos .py no importados:"
python3 - "$mod" <<'PY' 2>/dev/null || echo "  (no se pudo analizar)"
import re, sys
from pathlib import Path
issues = []
for init in Path(sys.argv[1]).rglob("__init__.py"):
    if "__pycache__" in str(init):
        continue
    pkg = init.parent
    imported = set(re.findall(r"^\s*from\s+\.\s+import\s+(.+)$", init.read_text(encoding="utf-8", errors="replace"), re.MULTILINE))
    imported = {n.strip() for line in imported for n in line.split(",")}
    for py in pkg.glob("*.py"):
        if py.name in ("__init__.py", "__manifest__.py"):
            continue
        if py.stem not in imported:
            issues.append(f"  {pkg.name}/{py.name} no esta importado en {pkg.name}/__init__.py")
print("\n".join(issues) if issues else "  (ok)")
PY

section "Artefactos commiteados (.pyc / __pycache__ en git):"
tracked="$(git -C "$mod" ls-files 2>/dev/null | grep -E '\.pyc$|__pycache__' | head -10)"
if [ -n "$tracked" ]; then echo "$tracked" | sed 's/^/  ⚠ /'; else echo "  (ninguno)"; fi

section "Politica de tests del repo (.swarm.conf):"
tests_policy="$(swarm_repo_conf TESTS "$mod/__manifest__.py")"
if [ "$tests_policy" = "required" ]; then
    if swarm_module_has_tests "$mod"; then
        n_tests="$(find "$mod/tests" -maxdepth 1 -name 'test_*.py' 2>/dev/null | wc -l | tr -d ' ')"
        echo "  TESTS=required (backend) — el modulo tiene tests/ con $n_tests test_*.py (verificar que cubran los flujos troncales del cambio)"
    else
        echo "  ⚠ TESTS=required (backend) y el modulo NO tiene tests/ con test_*.py — CRITICO segun checklist"
    fi
elif [ -n "$tests_policy" ]; then
    echo "  TESTS=$tests_policy (valor no estandar; solo 'required' activa la politica)"
else
    echo "  (el repo no declara politica de tests backend — no requeridos)"
fi

e2e_policy="$(swarm_repo_conf E2E "$mod/__manifest__.py")"
if [ "$e2e_policy" = "required" ]; then
    if swarm_module_has_e2e "$mod"; then
        echo "  E2E=required — el modulo tiene un tour (HttpCase.start_tour / web_tour.tours): verificar que cubra el flujo de UI del cambio y que al correrlo NO quede SKIPPED (Chrome)"
    elif swarm_module_has_ui "$mod"; then
        echo "  ⚠ E2E=required y el modulo tiene superficie de UI (controllers/JS) SIN tour: si el cambio toca un flujo de UI troncal, falta un tour — WARNING segun checklist"
    else
        echo "  E2E=required pero el modulo es backend puro (sin controllers/JS) — e2e NO aplica"
    fi
elif [ -n "$e2e_policy" ]; then
    echo "  E2E=$e2e_policy (valor no estandar; solo 'required' activa la politica)"
fi

# ── 4. Spec SDD (si aplica) ──
echo
spec="$(swarm_module_spec "$mod")"
if [ -n "$spec" ]; then
    echo "── Spec SDD (spec_lint.py) ──"
    python3 "$DIR/spec_lint.py" "$mod" 2>&1
else
    echo "── Spec SDD: el modulo no es SDD (sin specs/) ──"
fi

echo
echo "=== FIN — este reporte es INSUMO para @reviewer: las señales requieren juicio, no son veredictos. ==="
exit 0
