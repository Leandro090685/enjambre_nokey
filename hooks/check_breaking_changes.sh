#!/bin/bash
# Hook PostToolUse: detecta breaking changes de Odoo en archivos modificados.
#
# Version-agnostic: la version objetivo se lee de workspace.md (campo ODOO_VERSION)
# y los patrones prohibidos se cargan desde references/patterns/v{VERSION}.patterns.
# Agregar soporte para una version nueva = soltar un archivo de patrones; este script
# no se toca.
#
# Codigos de salida:
#   0 -> sin errores (los warnings se informan por stdout)
#   1 -> se detectaron breaking changes (el dispatcher lo convierte en bloqueo)

if [ $# -gt 0 ]; then
    files="$*"
else
    exit 0
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

# === Resolver ODOO_VERSION desde workspace.md (fallback: workspace.example.md) ===
ws="$ROOT/workspace.md"
[ -f "$ws" ] || ws="$ROOT/workspace.example.md"
[ -f "$ws" ] || exit 0  # sin config de entorno, no podemos validar

version=$(grep -oE '^[[:space:]]*ODOO_VERSION:[[:space:]]*[0-9]+' "$ws" 2>/dev/null | grep -oE '[0-9]+' | head -1)
[ -z "$version" ] && exit 0

patterns_file="$ROOT/references/patterns/v${version}.patterns"
# Si no hay patrones para esta version avisamos (NO bloqueamos): la validacion de breaking
# changes queda DESACTIVADA hasta crear el archivo. Un exit 0 silencioso aca hacia que un
# workspace sin patrones validara nada sin que nadie lo notara.
if [ ! -f "$patterns_file" ]; then
    echo "⚠️  No existe references/patterns/v${version}.patterns — validacion de breaking changes DESACTIVADA para ODOO_VERSION=${version}. Crea ese archivo (usa patterns/v19.patterns como modelo) para activarla."
    exit 0
fi

errors=0

for file in $files; do
    [ -f "$file" ] || continue

    case "$file" in
        *.py)  file_ext="py" ;;
        *.xml) file_ext="xml" ;;
        *.js)  file_ext="js" ;;
        *)     continue ;;
    esac

    # Recorrer cada patron del archivo de datos
    while IFS=$'\t' read -r ext pattern severity guard message; do
        # Saltar comentarios y lineas vacias del archivo de patrones
        case "$ext" in ''|\#*) continue ;; esac
        [ "$ext" = "$file_ext" ] || continue

        # Guard: si esta definido, el archivo debe contenerlo para que el patron aplique
        if [ -n "$guard" ] && [ "$guard" != "-" ]; then
            grep -q "$guard" "$file" 2>/dev/null || continue
        fi

        # Filtrar lineas de comentario segun el tipo de archivo
        if [ "$file_ext" = "xml" ]; then
            hits=$(grep -nE "$pattern" "$file" 2>/dev/null | grep -v '<!--')
        elif [ "$file_ext" = "js" ]; then
            hits=$(grep -nE "$pattern" "$file" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(//|\*)')
        else
            hits=$(grep -nE "$pattern" "$file" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#')
        fi

        [ -z "$hits" ] && continue

        if [ "$severity" = "warn" ]; then
            echo "⚠️  $file: $message"
        else
            echo "❌ $file: $message"
            errors=$((errors + 1))
        fi
        printf '%s\n' "$hits"
    done < "$patterns_file"
done

if [ $errors -gt 0 ]; then
    echo ""
    echo "=== Breaking Changes v${version} detectados: $errors ==="
    echo "Corregi estos errores antes de continuar. Detalle en references/ (ver patterns/v${version}.patterns)."
    exit 1
fi

exit 0
