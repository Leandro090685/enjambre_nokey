#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scripts/spec_lint.py — linter mecanico de specs SDD (skill sdd-specification).

Valida lo determinista que @reviewer (modo analyze) y @sdd-generate antes razonaban:
  - una sola spec en <modulo>/specs/
  - tabla de metadatos (Modulo, Version, Serie Odoo, Estado, Actualizado)
  - Estado dentro del ciclo de vida (draft|clarified|approved|analyzed|implemented|verified)
  - Version formato x.x.x y == version del __manifest__.py (sync)
  - secciones del formato canonico presentes (faltantes = WARN: "no burocracia")
  - cobertura CA <-> plan del cambio (tareas que referencian CA inexistentes = ERROR;
    CA sin tarea que lo cubra = WARN, el plan refleja solo el cambio en curso)
  - dependencias del plan (tareas inexistentes = ERROR; ciclos = ERROR)
  - anclajes al core `path:L#` (archivo inexistente o L# fuera de rango = ERROR)

El juicio semantico (¿la spec dice lo correcto?) sigue siendo del reviewer — esto solo
saca de opus la parte mecanica. Exit 0 sin errores (puede haber warnings), 1 con errores.

Uso: spec_lint.py <modulo_path | spec.md>
"""
import ast
import re
import sys
from pathlib import Path

VALID_STATES = {"draft", "clarified", "approved", "analyzed", "implemented", "verified"}
# Secciones del formato canonico (## ...). Faltantes = WARN (specs simples pueden omitir).
CANON_SECTIONS = [
    "Objetivo", "Decisiones vigentes", "Alcance", "Modelos", "Campos", "Metodos",
    "Vistas", "Seguridad", "Reglas de negocio", "Edge cases", "Criterios de aceptacion",
    "Referencias al core", "Documentacion afectada", "Plan del cambio",
]
# Estas si o si (una spec sin esto no orienta a nadie) = ERROR.
REQUIRED_SECTIONS = ["Objetivo", "Criterios de aceptacion"]

errors, warns, oks = [], [], []


def norm(s):
    """minusculas sin acentos, para comparar titulos de seccion."""
    return (s.lower().replace("á", "a").replace("é", "e").replace("í", "i")
            .replace("ó", "o").replace("ú", "u"))


def meta_value(text, key):
    """Valor de la fila '| **key** | valor |' de la tabla de metadatos (tolera variantes)."""
    m = re.search(r"^\|\s*\*\*" + key + r"[^|]*\*\*\s*\|\s*(.+?)\s*\|", text,
                  re.IGNORECASE | re.MULTILINE)
    return m.group(1).strip() if m else None


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    target = Path(sys.argv[1]).resolve()
    ws_root = Path(__file__).resolve().parent.parent.parent  # .claude/scripts -> workspace root

    # Resolver spec y modulo
    if target.is_file() and target.suffix == ".md":
        spec_path, module_dir = target, target.parent.parent
    elif target.is_dir():
        module_dir = target
        specs = sorted((target / "specs").glob("*.md")) if (target / "specs").is_dir() else []
        if not specs:
            print(f"ERROR: '{target}' no tiene specs/*.md (no es modulo SDD)", file=sys.stderr)
            return 1
        if len(specs) > 1:
            errors.append(f"specs/ tiene {len(specs)} archivos .md — la convencion es UNA spec por modulo: "
                          + ", ".join(s.name for s in specs))
        spec_path = specs[0]
    else:
        print(f"ERROR: '{target}' no existe", file=sys.stderr)
        return 2

    text = spec_path.read_text(encoding="utf-8", errors="replace")
    print(f"=== SPEC LINT: {spec_path} ===\n")

    # ── Metadatos (patrones tolerantes a tildes) ────────────────────────────
    META_KEYS = {"Modulo": r"M(?:o|ó)dulo", "Version": r"Versi(?:o|ó)n",
                 "Serie Odoo": r"Serie\s+Odoo", "Estado": r"Estado",
                 "Actualizado": r"Actualizad[oa]"}
    for key, pat in META_KEYS.items():
        val = meta_value(text, pat)
        if val is None:
            (errors if key in ("Version", "Estado") else warns).append(
                f"metadatos: falta la fila **{key}** en la tabla inicial")
        else:
            oks.append(f"metadatos: {key} = {val[:60]}")

    # Estado valido (primera palabra de la celda; las notas largas van aparte)
    state_raw = meta_value(text, "Estado") or ""
    m = re.search(r"[a-z_]+", state_raw.replace("`", "").replace("*", ""))
    state = m.group(0) if m else ""
    if state and state not in VALID_STATES:
        errors.append(f"Estado '{state}' fuera del ciclo de vida {sorted(VALID_STATES)}")
    elif state:
        oks.append(f"Estado '{state}' valido")

    # Version x.x.x y sync con manifest
    sver_m = re.search(r"(\d+\.\d+\.\d+)", meta_value(text, r"Versi(?:o|ó)n(?:\s+spec)?") or "")
    sver = sver_m.group(1) if sver_m else None
    if sver is None:
        errors.append("no pude extraer una Version x.x.x de la tabla de metadatos")
    else:
        if re.match(r"^\d{2}\.\d+\.", sver):
            warns.append(f"Version '{sver}' parece llevar prefijo de serie de Odoo — la convencion es x.x.x simple")
        manifest = module_dir / "__manifest__.py"
        if manifest.is_file():
            try:
                mver = (ast.literal_eval(manifest.read_text(encoding="utf-8")).get("version") or "").strip()
            except Exception:
                mver = ""
            if not mver:
                warns.append("no pude leer 'version' del __manifest__.py")
            elif mver != sver:
                errors.append(f"DRIFT de version: spec ({sver}) != manifest ({mver}) — sincronizar")
            else:
                oks.append(f"Version {sver} == manifest ✓")
        else:
            warns.append(f"no encontre __manifest__.py en {module_dir} (¿spec suelta?)")

    # ── Secciones ────────────────────────────────────────────────────────────
    headers = {norm(h.strip(" #").strip()) for h in re.findall(r"^#{2,3}\s+(.+)$", text, re.MULTILINE)}
    for sec in CANON_SECTIONS:
        present = any(norm(sec)[:20] in h for h in headers)
        if present:
            oks.append(f"seccion '{sec}' presente")
        elif sec in REQUIRED_SECTIONS:
            errors.append(f"seccion obligatoria '## {sec}' ausente")
        else:
            warns.append(f"seccion '## {sec}' ausente (ok si el modulo es simple y no aplica)")

    # ── CA y plan del cambio ─────────────────────────────────────────────────
    cas = set(re.findall(r"\bCA(\d{2,3})\b", text))
    ca_defined = {f"CA{n}" for n in re.findall(r"\*\*CA(\d{2,3})\*\*", text)} or \
                 {f"CA{n}" for n in cas}
    # Tareas del plan: filas "| **T01** ... | ..." (la celda del ID puede llevar anotaciones)
    task_rows = re.findall(r"^\|\s*\*\*(T\d{2,3}[a-z]?)\*\*[^|]*\|(.+)$", text, re.MULTILINE)
    tasks = {}
    for tid, rest in task_rows:
        cells = [c.strip() for c in rest.split("|")]
        # celdas: descripcion, depende de, archivos, cubre (formato canonico de 5 columnas)
        deps = re.findall(r"\bT\d{2,3}[a-z]?\b", cells[1]) if len(cells) > 1 else []
        # rango "T01..T05" cubre los intermedios: expandir
        for a, b in re.findall(r"\bT(\d{2,3})\.\.T(\d{2,3})\b", cells[1] if len(cells) > 1 else ""):
            deps += [f"T{n:02d}" for n in range(int(a), int(b) + 1)]
        covers = re.findall(r"\bCA\d{2,3}\b", cells[3]) if len(cells) > 3 else []
        tasks[tid] = {"deps": set(deps), "covers": set(covers)}

    if tasks:
        oks.append(f"plan del cambio: {len(tasks)} tareas ({', '.join(sorted(tasks))})")
        # deps inexistentes / ciclos
        for tid, t in tasks.items():
            missing = {d for d in t["deps"] if d not in tasks and d != tid}
            if missing:
                errors.append(f"{tid} depende de tareas inexistentes: {', '.join(sorted(missing))}")
        # ciclo por DFS simple
        WHITE, GRAY, BLACK = 0, 1, 2
        color = {t: WHITE for t in tasks}

        def dfs(u):
            color[u] = GRAY
            for v in tasks[u]["deps"]:
                if v not in tasks:
                    continue
                if color[v] == GRAY:
                    return True
                if color[v] == WHITE and dfs(v):
                    return True
            color[u] = BLACK
            return False

        if any(dfs(t) for t in tasks if color[t] == WHITE):
            errors.append("el plan del cambio tiene un CICLO de dependencias")
        # tareas que cubren CA inexistentes
        for tid, t in tasks.items():
            ghost = {c for c in t["covers"] if c not in ca_defined}
            if ghost:
                errors.append(f"{tid} dice cubrir CA inexistentes: {', '.join(sorted(ghost))}")
        # CA sin cobertura (WARN: el plan refleja solo el cambio en curso)
        covered = set().union(*(t["covers"] for t in tasks.values())) if tasks else set()
        uncovered = sorted(ca_defined - covered)
        if uncovered:
            warns.append(f"CA sin tarea que los cubra en el plan actual: {', '.join(uncovered)} "
                         "(ok si son de cambios ya implementados)")
        else:
            oks.append("cobertura CA↔tareas completa")
    elif ca_defined:
        warns.append("hay CA definidos pero no encontre plan del cambio con tareas T01.. "
                     "(ok si la spec esta verified y el plan se vacio)")

    # ── Anclajes al core (path:L#) ───────────────────────────────────────────
    anchors = re.findall(r"`([\w./\-]+\.(?:py|xml|js|csv)):L?(\d+)`", text)
    if anchors:
        core_index = {}  # basename -> [paths]; se construye solo si hace falta (nombres pelados)

        def core_lookup(basename):
            if not core_index:
                for root in (ws_root / "odoo" / "addons", ws_root / "enterprise",
                             ws_root / "odoo" / "odoo"):
                    if root.is_dir():
                        for p in root.rglob(basename):
                            core_index.setdefault(basename, []).append(p)
                core_index.setdefault(basename, [])
            elif basename not in core_index:
                core_index[basename] = []
                for root in (ws_root / "odoo" / "addons", ws_root / "enterprise",
                             ws_root / "odoo" / "odoo"):
                    if root.is_dir():
                        core_index[basename].extend(root.rglob(basename))
            return core_index[basename]

        def line_count(f):
            return sum(1 for _ in f.open(encoding="utf-8", errors="replace"))

        seen = set()
        for path, line in anchors:
            if (path, line) in seen:
                continue
            seen.add((path, line))
            # Candidatos, en orden: workspace root · el modulo · el repo del modulo (hermanos) ·
            # core/enterprise con el path tal cual · nombre pelado -> por basename en el modulo
            # y en el core (los anclajes suelen omitir el prefijo del arbol).
            bases = [ws_root, module_dir, module_dir.parent,
                     ws_root / "odoo" / "addons", ws_root / "enterprise", ws_root / "odoo"]
            if path.startswith("/"):
                bases = [Path("/")]
            candidates = [b / path for b in bases if (b / path).is_file()]
            if "/" not in path:
                candidates += sorted(module_dir.rglob(path)) + core_lookup(path)
            # dedup conservando orden
            uniq, s = [], set()
            for c in candidates:
                r = c.resolve()
                if r not in s:
                    uniq.append(c)
                    s.add(r)
            if not uniq:
                errors.append(f"anclaje roto: `{path}` no existe (workspace/modulo/repo/core)")
                continue
            # nombre ambiguo: OK si ALGUN candidato alcanza la linea citada
            if not any(int(line) <= line_count(c) for c in uniq):
                n = line_count(uniq[0])
                errors.append(f"anclaje fuera de rango: `{path}:L{line}` "
                              f"(ningun candidato llega a esa linea; el primero tiene {n})")
        oks.append(f"anclajes verificados: {len(seen)}")
    else:
        warns.append("sin anclajes `path:L#` verificables (ok si el modulo no toca core)")

    # ── Reporte ──────────────────────────────────────────────────────────────
    for e in errors:
        print(f"[ERROR] {e}")
    for w in warns:
        print(f"[WARN]  {w}")
    print(f"\nResumen: {len(errors)} errores · {len(warns)} warnings · {len(oks)} checks OK")
    if errors:
        print("→ Corregir los ERROR antes de dar la spec por 'analyzed'.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
# vim:expandtab:smartindent:tabstop=4:softtabstop=4:shiftwidth=4:
