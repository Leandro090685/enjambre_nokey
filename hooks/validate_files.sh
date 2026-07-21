#!/bin/bash
# Valida convenciones del proyecto (headers, modelines, sintaxis, manifest, docs) en los
# archivos pasados como argumentos. Warnings informativos (exit 0); no bloquea.

LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$LIBDIR/lib.sh"

# Interprete de Python para py_compile: preferir python3, caer a python.
if command -v python3 >/dev/null 2>&1; then
    PY=python3
elif command -v python >/dev/null 2>&1; then
    PY=python
else
    PY=""
fi

# Si hay argumentos (archivos modificados), usarlos.
# Si no, buscar archivos .py/.xml modificados en los ultimos 5 minutos dentro de
# las raices de addons custom (declaradas en workspace.md, o extra-addons/ por defecto).
if [ $# -gt 0 ]; then
    files="$*"
else
    files=$(swarm_addons_search_dirs | while IFS= read -r d; do
        [ -d "$d" ] && find "$d" \( -name "*.py" -o -name "*.xml" \) 2>/dev/null
    done | while read -r f; do
        if [ -n "$(find "$f" -mmin -5 2>/dev/null)" ]; then
            echo "$f"
        fi
    done)
fi

if [ -z "$files" ]; then
    exit 0
fi

errors=0
warnings=0
checked=0

for file in $files; do
    # Saltar archivos que no existen o no son regulares
    [ -f "$file" ] || continue
    checked=$((checked + 1))

    # Banner de licencia prohibido en archivos (v17+): la licencia se declara solo en
    # __manifest__.py. Repetir el banner AGPL/GPL en cada .py/.xml es ruido.
    if [[ "$file" == *.py || "$file" == *.xml ]]; then
        if grep -qE 'GNU Affero|This program is free software|GNU (Lesser )?General Public License' "$file"; then
            echo "⚠️  $file: banner de licencia en el archivo (prohibido v17+; la licencia va solo en manifest — AGENTS.md § encabezados)"
            warnings=$((warnings + 1))
        fi
    fi

    # Validar archivos Python
    if [[ "$file" == *.py ]]; then
        # Header UTF-8
        if ! head -1 "$file" | grep -q "# -\*- coding: utf-8 -\*-"; then
            echo "⚠️  $file: falta header '# -*- coding: utf-8 -*-'"
            warnings=$((warnings + 1))
        fi

        # Vim modeline (ultima linea sin espacios en blanco)
        if ! grep -q "# vim:expandtab:smartindent:tabstop=4:softtabstop=4:shiftwidth=4:" "$file"; then
            echo "⚠️  $file: falta vim modeline footer"
            warnings=$((warnings + 1))
        fi

        # Validar sintaxis (si hay interprete disponible).
        # Compilamos el .pyc a un temporal en /tmp: el __pycache__ del modulo suele
        # ser de root (lo crea el contenedor Docker) y "py_compile -m" fallaria por
        # permisos, dando un falso "error de sintaxis". doraise=True solo levanta
        # PyCompileError ante errores reales de sintaxis.
        if [ -n "$PY" ]; then
            tmp_pyc="/tmp/swarm_pychk_$$.pyc"
            if ! "$PY" -c "import sys,py_compile; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)" "$file" "$tmp_pyc" >/dev/null 2>&1; then
                echo "❌ $file: error de sintaxis Python"
                errors=$((errors + 1))
            fi
            rm -f "$tmp_pyc"
        fi
    fi

    # Validar archivos XML
    if [[ "$file" == *.xml ]]; then
        # Header XML
        if ! head -1 "$file" | grep -q '<?xml version="1.0" encoding="utf-8"?>'; then
            echo "⚠️  $file: falta header XML"
            warnings=$((warnings + 1))
        fi

        # Vim modeline
        if ! grep -q '<!-- vim:expandtab:smartindent:tabstop=4:softtabstop=4:shiftwidth=4-->' "$file"; then
            echo "⚠️  $file: falta vim modeline footer"
            warnings=$((warnings + 1))
        fi

        # Validar well-formed
        if command -v xmllint >/dev/null 2>&1; then
            if ! xmllint --noout "$file" 2>/dev/null; then
                echo "❌ $file: XML no esta well-formed"
                errors=$((errors + 1))
            fi
        fi
    fi

    # Validar __manifest__.py
    if [[ "$(basename "$file")" == "__manifest__.py" ]]; then
        # Chequeo suave: el manifest debe declarar license (cualquiera; default del proyecto LGPL-3).
        if ! grep -qE '["'\'']license["'\'']' "$file"; then
            echo "⚠️  $file: manifest sin clave 'license'"
            warnings=$((warnings + 1))
        fi

        # Formato de version: x.x.x simple, SIN prefijo de serie de Odoo (Odoo la antepone solo).
        # {serie}.1.0.0 (ej. 19.1.0.0) deja el modulo uninstallable; {serie}.0.x.y desaconsejado.
        ver=$(swarm_manifest_version "$(dirname "$file")")
        if [ -n "$ver" ] && ! printf '%s' "$ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "⚠️  $file: version '$ver' no es 'x.x.x' simple. Usá '1.0.0' SIN prefijo de serie (Odoo la antepone). '{serie}.1.0.0' deja el modulo UNINSTALLABLE — AGENTS.md § Manifest."
            warnings=$((warnings + 1))
        fi
    fi

    # Documentacion del modulo (README.md + index.html), si el archivo es de un modulo custom.
    module_dir=$(swarm_module_root "$file")
    if [ -n "$module_dir" ]; then
        if [ ! -f "$module_dir/README.md" ] && [ ! -f "$module_dir/static/description/index.html" ]; then
            echo "📄 $module_dir: modulo sin documentacion (falta README.md e index.html)"
            warnings=$((warnings + 1))
        fi
    fi
done

if [ $checked -eq 0 ]; then
    exit 0
fi

echo ""
echo "=== Validacion de convenciones ==="
echo "   Archivos revisados: $checked"
echo "   Warnings: $warnings"
echo "   Errores: $errors"

if [ $errors -gt 0 ]; then
    echo "❌ Hay errores criticos que deben corregirse."
    exit 1
elif [ $warnings -gt 0 ]; then
    echo "⚠️  Hay warnings — revisar antes de commitear."
fi

exit 0
