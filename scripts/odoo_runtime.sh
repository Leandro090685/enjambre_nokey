#!/bin/bash
# scripts/odoo_runtime.sh — wrapper de runtime Odoo para agentes y skills.
#
# Resuelve UNA vez el entorno (engine/contenedor/DB o venv) desde workspace.md via hooks/lib.sh
# y expone subcomandos fijos, para que los agentes no re-armen comandos docker/psql en cada corrida.
# Consumidores: @testing, skill debugging-odoo.
#
# Marcadores usados (workspace.md): ODOO_CONTAINER, ODOO_DB_CONTAINER, ODOO_CONTAINER_ENGINE,
# ODOO_DB_USER (opcional, default "odoo"), ODOO_BIN (opcional, modo venv: comando completo de odoo),
# ODOO_LOGFILE (opcional, modo venv).
#
# Uso: odoo_runtime.sh <subcomando> [args]
#   env                              muestra el entorno resuelto
#   ps                               contenedores corriendo (engine ps)
#   logs [--follow] [--tail N] [--grep PATRON]
#   errors [--tail N]                atajo: logs filtrados por error|critical|traceback
#   shell <db>                       imprime el comando interactivo (no lo ejecuta: requiere TTY)
#   upgrade <db> <mod1[,mod2..]>     odoo -u --stop-after-init
#   install <db> <mod1[,mod2..]>     odoo -i --stop-after-init
#   test <db> <modulos> [--test-tags TAGS]   upgrade con --test-enable (o solo --test-tags)
#   run-tests <db> <TAGS>            odoo --test-tags TAGS --stop-after-init
#   chrome-check                     ¿hay Chrome en el runtime? (para tours e2e) -> CHROME=<path>|missing
#   chrome-install                   instala chromium en el contenedor (tours e2e; pedir confirmacion antes)
#   psql <db> [-c SQL]               psql contra la DB (sin -c lee de stdin)
#   backup <db> [outfile.sql.gz]     pg_dump | gzip (default: backup_<db>_<ts>.sql.gz en cwd)
#   restore <db> <file.sql.gz> --yes restaura un backup (DESTRUCTIVO: pide --yes)
#   validate <modulo_path>           py_compile + xmllint + IDs XML duplicados del modulo
#   dup-ids <modulo_path>            solo IDs XML duplicados
#   deps <module_name>               modulos que dependen de el (para testing de regresion)

set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/../hooks/lib.sh" 2>/dev/null || { echo "ERROR: no se pudo cargar hooks/lib.sh" >&2; exit 1; }

ENGINE="$(swarm_container_engine)"
CONTAINER="$(swarm_ws_marker ODOO_CONTAINER)"
DB_CONTAINER="$(swarm_ws_marker ODOO_DB_CONTAINER)"
DB_USER="${ODOO_DB_USER:-$(swarm_ws_marker ODOO_DB_USER)}"; [ -n "$DB_USER" ] || DB_USER="odoo"
ODOO_BIN_MARK="$(swarm_ws_marker ODOO_BIN)"
LOGFILE="$(swarm_ws_marker ODOO_LOGFILE)"

die() { echo "ERROR: $*" >&2; exit 1; }

# Modo: contenedor (hay ODOO_CONTAINER) o venv/local (ODOO_BIN). Falla claro si no hay ninguno.
mode() {
    if [ -n "$CONTAINER" ]; then echo container
    elif [ -n "$ODOO_BIN_MARK" ]; then echo venv
    else echo none; fi
}

require_runtime() {
    case "$(mode)" in
        none) die "workspace.md no declara ODOO_CONTAINER ni ODOO_BIN — no se como correr Odoo" ;;
        container) command -v "$ENGINE" >/dev/null 2>&1 || die "engine '$ENGINE' no disponible en el host" ;;
    esac
}

# Ejecuta el binario odoo (no interactivo) con los args dados.
odoo_exec() {
    require_runtime
    if [ "$(mode)" = "container" ]; then
        "$ENGINE" exec "$CONTAINER" odoo "$@"
    else
        # ODOO_BIN puede ser un comando con espacios (ej. "venv/bin/python odoo/odoo-bin")
        # shellcheck disable=SC2086
        $ODOO_BIN_MARK "$@"
    fi
}

# Ejecuta un comando de postgres (psql/pg_dump) contra la DB, con stdin conectado.
db_exec() {
    if [ -n "$DB_CONTAINER" ]; then
        command -v "$ENGINE" >/dev/null 2>&1 || die "engine '$ENGINE' no disponible en el host"
        "$ENGINE" exec -i "$DB_CONTAINER" "$@"
    else
        "$@"
    fi
}

cmd="${1:-}"; [ -n "$cmd" ] && shift || { grep '^#   ' "$0" | sed 's/^#   //'; exit 1; }

case "$cmd" in

env)
    echo "modo         : $(mode)"
    echo "engine       : $ENGINE"
    echo "contenedor   : ${CONTAINER:-(no declarado)} [$(swarm_docker_status)]"
    echo "db container : ${DB_CONTAINER:-(no declarado — psql/pg_dump directo en host)}"
    echo "db user      : $DB_USER"
    [ -n "$ODOO_BIN_MARK" ] && echo "odoo bin     : $ODOO_BIN_MARK"
    [ -n "$LOGFILE" ] && echo "logfile      : $LOGFILE"
    exit 0
    ;;

ps)
    require_runtime
    [ "$(mode)" = "container" ] || die "modo venv: no hay contenedores que listar"
    "$ENGINE" ps
    ;;

logs)
    follow=0; tail_n=200; pattern=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -f|--follow) follow=1 ;;
            --tail) tail_n="$2"; shift ;;
            --grep) pattern="$2"; shift ;;
            *) die "logs: argumento desconocido '$1'" ;;
        esac; shift
    done
    require_runtime
    if [ "$(mode)" = "container" ]; then
        if [ "$follow" = 1 ]; then
            if [ -n "$pattern" ]; then "$ENGINE" logs -f "$CONTAINER" 2>&1 | grep -i "$pattern"
            else "$ENGINE" logs -f "$CONTAINER"; fi
        else
            if [ -n "$pattern" ]; then "$ENGINE" logs --tail "$tail_n" "$CONTAINER" 2>&1 | grep -i "$pattern"
            else "$ENGINE" logs --tail "$tail_n" "$CONTAINER" 2>&1; fi
        fi
    else
        [ -n "$LOGFILE" ] || die "modo venv sin marcador ODOO_LOGFILE — logs salen por stdout del proceso"
        if [ "$follow" = 1 ]; then
            if [ -n "$pattern" ]; then tail -f "$LOGFILE" | grep -i "$pattern"; else tail -f "$LOGFILE"; fi
        else
            if [ -n "$pattern" ]; then tail -n "$tail_n" "$LOGFILE" | grep -i "$pattern"; else tail -n "$tail_n" "$LOGFILE"; fi
        fi
    fi
    ;;

errors)
    tail_n=200
    [ "${1:-}" = "--tail" ] && { tail_n="$2"; }
    "$0" logs --tail "$tail_n" --grep 'error\|critical\|traceback'
    ;;

shell)
    db="${1:-}"; [ -n "$db" ] || die "uso: shell <db>"
    require_runtime
    # Interactivo: no lo ejecutamos (los agentes no tienen TTY); imprimimos el comando listo.
    if [ "$(mode)" = "container" ]; then
        echo "$ENGINE exec -it $CONTAINER odoo shell -d $db"
    else
        echo "$ODOO_BIN_MARK shell -d $db"
    fi
    ;;

upgrade|install)
    db="${1:-}"; mods="${2:-}"
    [ -n "$db" ] && [ -n "$mods" ] || die "uso: $cmd <db> <mod1[,mod2..]>"
    flag="-u"; [ "$cmd" = "install" ] && flag="-i"
    odoo_exec -d "$db" "$flag" "$mods" --stop-after-init
    ;;

test)
    db="${1:-}"; mods="${2:-}"; shift 2 2>/dev/null || die "uso: test <db> <mod1[,mod2..]> [--test-tags TAGS]"
    tags=""
    [ "${1:-}" = "--test-tags" ] && tags="$2"
    if [ -n "$tags" ]; then
        odoo_exec -d "$db" -u "$mods" --test-tags "$tags" --stop-after-init
    else
        odoo_exec -d "$db" -u "$mods" --test-enable --stop-after-init
    fi
    ;;

run-tests)
    db="${1:-}"; tags="${2:-}"
    [ -n "$db" ] && [ -n "$tags" ] || die "uso: run-tests <db> <TAGS>  (ej: run-tests mi_db /mi_modulo:TestClase)"
    odoo_exec -d "$db" --test-tags "$tags" --stop-after-init
    ;;

chrome-check)
    # Los tours e2e (HttpCase.start_tour) necesitan Chrome/chromium en el runtime; sin el, Odoo
    # SALTEA el tour (no falla) -> un run se veria verde sin probar nada. @testing gatea con esto.
    require_runtime
    # ODOO_BROWSER_BIN (env) tiene prioridad en Odoo; despues busca estos binarios en el PATH.
    check='for b in "$ODOO_BROWSER_BIN" chromium chromium-browser google-chrome google-chrome-stable; do [ -n "$b" ] && command -v "$b" >/dev/null 2>&1 && { echo "CHROME=$(command -v "$b")"; exit 0; }; done; echo "CHROME=missing"; exit 1'
    if [ "$(mode)" = "container" ]; then
        "$ENGINE" exec "$CONTAINER" sh -c "$check"
    else
        sh -c "$check"
    fi
    ;;

chrome-install)
    # Instala chromium en el contenedor para habilitar los tours e2e. MUTA el contenedor:
    # correr SOLO tras confirmacion del usuario (el orquestador pregunta; no es automatico).
    # Nota: apt-get dentro del contenedor persiste al restart pero se PIERDE si se recrea la
    # imagen/contenedor — para permanencia, agregar chromium al Dockerfile de la imagen dev.
    require_runtime
    [ "$(mode)" = "container" ] || die "chrome-install: solo en modo contenedor (en venv instala Chrome en el host a mano o seteá ODOO_BROWSER_BIN)"
    if "$0" chrome-check >/dev/null 2>&1; then
        echo "Chrome ya presente en '$CONTAINER' — nada que hacer:"; "$0" chrome-check; exit 0
    fi
    echo "Instalando chromium en el contenedor '$CONTAINER' (apt-get, como root)…" >&2
    "$ENGINE" exec -u root "$CONTAINER" sh -c 'apt-get update && apt-get install -y --no-install-recommends chromium' \
        || die "no se pudo instalar chromium (¿imagen no-Debian? ¿sin red? ¿sin permisos?) — instalalo a mano o seteá ODOO_BROWSER_BIN"
    echo "── verificacion ──"
    "$0" chrome-check
    ;;

psql)
    db="${1:-}"; [ -n "$db" ] || die "uso: psql <db> [-c SQL]  (sin -c lee SQL de stdin)"
    shift
    db_exec psql -U "$DB_USER" -d "$db" "$@"
    ;;

backup)
    db="${1:-}"; [ -n "$db" ] || die "uso: backup <db> [outfile.sql.gz]"
    out="${2:-backup_${db}_$(date +%Y%m%d_%H%M%S).sql.gz}"
    db_exec pg_dump -U "$DB_USER" "$db" | gzip > "$out" || die "pg_dump fallo"
    # pg_dump vacio = algo salio mal (DB inexistente, permisos)
    [ -s "$out" ] || { rm -f "$out"; die "backup vacio — revisar nombre de DB/permisos"; }
    echo "BACKUP_FILE=$out ($(du -h "$out" | cut -f1))"
    ;;

restore)
    db="${1:-}"; file="${2:-}"; yes="${3:-}"
    [ -n "$db" ] && [ -n "$file" ] || die "uso: restore <db> <file.sql.gz> --yes"
    [ "$yes" = "--yes" ] || die "restore es DESTRUCTIVO (pisa la DB '$db'): confirmá agregando --yes"
    [ -f "$file" ] || die "no existe el archivo '$file'"
    case "$file" in
        *.gz) gunzip -c "$file" | db_exec psql -U "$DB_USER" -d "$db" ;;
        *)    db_exec psql -U "$DB_USER" -d "$db" < "$file" ;;
    esac
    ;;

validate)
    mod="${1:-}"; [ -n "$mod" ] && [ -d "$mod" ] || die "uso: validate <modulo_path>"
    rc=0
    echo "── py_compile ──"
    py_err=0
    # Compilar a un .pyc en /tmp: el __pycache__ del modulo suele ser de root (lo crea el contenedor)
    tmp_pyc="$(mktemp -u "${TMPDIR:-/tmp}/swarm_validate_XXXXXX.pyc")"
    while IFS= read -r f; do
        out="$(python3 -c "import sys,py_compile; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)" "$f" "$tmp_pyc" 2>&1)" \
            || { echo "FAIL: $f"; echo "$out" | sed 's/^/  /'; py_err=$((py_err+1)); }
    done < <(find "$mod" -name "*.py" -not -path "*/__pycache__/*" 2>/dev/null)
    rm -f "$tmp_pyc"
    [ "$py_err" = 0 ] && echo "OK (0 errores)" || rc=1
    echo
    echo "── XML well-formed ──"
    xml_err=0
    while IFS= read -r f; do
        if command -v xmllint >/dev/null 2>&1; then
            out="$(xmllint --noout "$f" 2>&1)" || { echo "FAIL: $f"; echo "$out" | sed 's/^/  /'; xml_err=$((xml_err+1)); }
        else
            out="$(python3 -c "import sys,xml.etree.ElementTree as ET; ET.parse(sys.argv[1])" "$f" 2>&1)" \
                || { echo "FAIL: $f"; echo "$out" | tail -1 | sed 's/^/  /'; xml_err=$((xml_err+1)); }
        fi
    done < <(find "$mod" -name "*.xml" 2>/dev/null)
    [ "$xml_err" = 0 ] && echo "OK (0 errores)" || rc=1
    echo
    echo "── IDs XML duplicados ──"
    dups="$(find "$mod" -name "*.xml" -exec grep -ho '<record[^>]* id="[^"]*"' {} + 2>/dev/null \
        | grep -o 'id="[^"]*"' | sort | uniq -d)"
    if [ -n "$dups" ]; then echo "$dups"; echo "(revisar: puede ser herencia legitima de vista con mismo XML ID)"; else echo "OK (sin duplicados)"; fi
    exit "$rc"
    ;;

dup-ids)
    mod="${1:-}"; [ -n "$mod" ] && [ -d "$mod" ] || die "uso: dup-ids <modulo_path>"
    find "$mod" -name "*.xml" -exec grep -ho '<record[^>]* id="[^"]*"' {} + 2>/dev/null \
        | grep -o 'id="[^"]*"' | sort | uniq -d
    ;;

deps)
    name="${1:-}"; [ -n "$name" ] || die "uso: deps <module_name>"
    # Modulos custom cuyo __manifest__.py declara dependencia sobre <name>
    while IFS= read -r root; do
        [ -n "$root" ] && [ -d "$root" ] || continue
        grep -rl --include="__manifest__.py" -E "[\"']${name}[\"']" "$root" 2>/dev/null
    done < <(swarm_addons_roots) | while IFS= read -r mf; do
        # confirmar que aparece dentro de 'depends' (no en description)
        python3 - "$mf" "$name" <<'PY'
import ast, sys
try:
    d = ast.literal_eval(open(sys.argv[1], encoding="utf-8").read())
    if sys.argv[2] in (d.get("depends") or []):
        print(sys.argv[1].rsplit("/__manifest__.py", 1)[0])
except Exception:
    pass
PY
    done
    ;;

*)
    die "subcomando desconocido '$cmd' (correr sin args para ver la ayuda)"
    ;;
esac
