#!/bin/bash
# scripts/extract_docx.sh — ingesta determinista de insumos .docx para @feature-analyst.
#
# Extrae texto e imagenes embebidas con una cadena de fallback fija (pandoc → libreoffice →
# docx2txt → python-docx → unzip), que antes el agente re-decidia/tecleaba en cada corrida.
# Las imagenes SIEMPRE se extraen (un .docx es un zip: word/media/*), independiente del metodo
# de texto. Read-only sobre el insumo.
#
# Uso: extract_docx.sh <archivo.docx> [outdir]
#   outdir default: ${TMPDIR:-/tmp}/swarm_docx_<basename>
# Salida (lineas parseables al final):
#   METHOD=<pandoc|libreoffice|docx2txt|python-docx|unzip>
#   TEXT_FILE=<path del texto extraido>
#   MEDIA_DIR=<dir con imagenes>  +  IMAGES=<n>
# El agente luego LEE TEXT_FILE y cada imagen de MEDIA_DIR con la tool Read.

set -u

docx="${1:-}"
[ -n "$docx" ] && [ -f "$docx" ] || { echo "uso: extract_docx.sh <archivo.docx> [outdir]" >&2; exit 1; }

base="$(basename "$docx")"; base="${base%.*}"
outdir="${2:-${TMPDIR:-/tmp}/swarm_docx_${base}}"
mkdir -p "$outdir" || { echo "ERROR: no pude crear '$outdir'" >&2; exit 1; }
txt="$outdir/document.md"
media="$outdir/media"

method=""

# ── Texto: cadena de fallback ────────────────────────────────────────────────
if command -v pandoc >/dev/null 2>&1; then
    # pandoc extrae texto (gfm conserva tablas) y media en un paso
    if pandoc "$docx" -t gfm --extract-media="$outdir" -o "$txt" 2>/dev/null && [ -s "$txt" ]; then
        method="pandoc"
    fi
fi

if [ -z "$method" ]; then
    lo=""; command -v libreoffice >/dev/null 2>&1 && lo="libreoffice"
    [ -z "$lo" ] && command -v soffice >/dev/null 2>&1 && lo="soffice"
    if [ -n "$lo" ]; then
        if timeout 60 "$lo" --headless --convert-to txt:Text --outdir "$outdir" "$docx" >/dev/null 2>&1 \
            && [ -s "$outdir/$base.txt" ]; then
            mv "$outdir/$base.txt" "$txt"
            method="libreoffice"
        fi
    fi
fi

if [ -z "$method" ] && command -v docx2txt >/dev/null 2>&1; then
    if docx2txt "$docx" - > "$txt" 2>/dev/null && [ -s "$txt" ]; then
        method="docx2txt"
    fi
fi

if [ -z "$method" ] && command -v python3 >/dev/null 2>&1; then
    if python3 - "$docx" > "$txt" 2>/dev/null <<'PY' && [ -s "$txt" ]; then
import sys
from docx import Document
d = Document(sys.argv[1])
for p in d.paragraphs:
    if p.text.strip():
        print(p.text)
for t in d.tables:
    for r in t.rows:
        print(" | ".join(c.text.strip() for c in r.cells))
PY
        method="python-docx"
    fi
fi

if [ -z "$method" ]; then
    # Fallback universal: un .docx es un zip; el texto vive en word/document.xml (<w:t>)
    if command -v unzip >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        unzip -o "$docx" word/document.xml -d "$outdir/raw" >/dev/null 2>&1
        if [ -f "$outdir/raw/word/document.xml" ]; then
            python3 - "$outdir/raw/word/document.xml" > "$txt" 2>/dev/null <<'PY'
import sys, xml.etree.ElementTree as ET
NS = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
root = ET.parse(sys.argv[1]).getroot()
for p in root.iter(NS + "p"):
    line = "".join(t.text or "" for t in p.iter(NS + "t"))
    if line.strip():
        print(line)
PY
            [ -s "$txt" ] && method="unzip"
        fi
    fi
fi

[ -n "$method" ] || { echo "ERROR: no pude extraer texto de '$docx' con ninguna herramienta (pandoc/libreoffice/docx2txt/python-docx/unzip) — pedir el contenido en texto" >&2; exit 1; }

# ── Imagenes: SIEMPRE via unzip (pandoc ya pudo haberlas dejado en $outdir/media) ──
if [ ! -d "$media" ] || [ -z "$(ls -A "$media" 2>/dev/null)" ]; then
    mkdir -p "$media"
    if command -v unzip >/dev/null 2>&1; then
        unzip -jo "$docx" 'word/media/*' -d "$media" >/dev/null 2>&1
    fi
fi
n_img="$(find "$media" -type f 2>/dev/null | wc -l | tr -d ' ')"

echo "METHOD=$method"
echo "TEXT_FILE=$txt ($(wc -l < "$txt" | tr -d ' ') lineas)"
echo "MEDIA_DIR=$media"
echo "IMAGES=$n_img"
if [ "$n_img" -gt 0 ]; then
    find "$media" -type f | sort | sed 's/^/  /'
    echo "→ Leer cada imagen con la tool Read (interpreta imagenes) e incorporarlas al analisis."
fi
exit 0
