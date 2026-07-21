#!/bin/bash
# hooks/lib.sh — helpers compartidos por los hooks del enjambre.
#
# Resuelve la ubicacion de core/enterprise y addons custom desde workspace.md, con
# deteccion estructural por defecto (un modulo es custom si tiene __manifest__.py
# ancestro y no esta bajo core/enterprise; ningun layout se asume). El esquema de
# marcadores (handles + listas CORE_ROOTS/CLIENT_ADDONS/PRODUCT_ADDONS) y sus defaults
# estan documentados en workspace.example.md.

# Rutas resueltas al sourcear (absolutas; ${BASH_SOURCE} dentro de funciones falla en zsh).
NOKEY_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOKEY_CLAUDE_DIR="$(cd "$NOKEY_HOOK_DIR/.." && pwd)"
NOKEY_WS_ROOT="$(cd "$NOKEY_CLAUDE_DIR/.." && pwd)"

# Archivo de entorno: workspace.md, con fallback a workspace.example.md.
swarm_workspace_file() {
    if [ -f "$NOKEY_CLAUDE_DIR/workspace.md" ]; then
        printf '%s' "$NOKEY_CLAUDE_DIR/workspace.md"
    elif [ -f "$NOKEY_CLAUDE_DIR/workspace.example.md" ]; then
        printf '%s' "$NOKEY_CLAUDE_DIR/workspace.example.md"
    fi
}

# Lee un marcador "KEY: val1 val2 ..." de workspace.md. Echo de los valores
# (sin comentario final). Vacio si el marcador no existe.
swarm_ws_marker() {
    local key="$1" ws; ws="$(swarm_workspace_file)"
    [ -n "$ws" ] && [ -f "$ws" ] || return 0
    grep -oE "^[[:space:]]*${key}:[[:space:]]*.*" "$ws" 2>/dev/null \
        | head -1 \
        | sed -E "s/^[[:space:]]*${key}:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//"
}

# Override opcional del workspace root (marcador WORKSPACE_ROOT, con expansion de ~).
_swarm_ws_override="$(swarm_ws_marker WORKSPACE_ROOT)"
if [ -n "$_swarm_ws_override" ]; then
    case "$_swarm_ws_override" in "~"*) _swarm_ws_override="$HOME${_swarm_ws_override#\~}" ;; esac
    NOKEY_WS_ROOT="$_swarm_ws_override"
fi
unset _swarm_ws_override

# Workspace root = carpeta que contiene .claude/ (o el override de WORKSPACE_ROOT).
swarm_workspace_root() { printf '%s' "$NOKEY_WS_ROOT"; }

# ── Secretos per-dev (FUERA del repo) ────────────────────────────────────────
# Los secretos (tokens/passwords) NO viven en el repo del enjambre: viven en un
# archivo en un path comun bajo el HOME del dev. El path se declara con el marcador
# NOKEY_SECRETS_FILE en workspace.md; si falta, se usa el default. El archivo usa formato KEY=value
# (a diferencia de workspace.md, que usa KEY: value).

# Echo del path del archivo de secretos (con expansion de ~). Default: ~/.claude/nokey-enjambre-secrets.env
swarm_secrets_file() {
    local p; p="$(swarm_ws_marker NOKEY_SECRETS_FILE)"
    [ -n "$p" ] || p="$HOME/.claude/nokey-enjambre-secrets.env"
    case "$p" in "~"*) p="$HOME${p#\~}" ;; esac
    printf '%s' "$p"
}

# Carga KEY=value del archivo de secretos al entorno (export), SIN pisar vars ya seteadas (asi un
# override por env/Claude settings gana). Parser linea a linea (NO 'source'/'eval': seguridad).
swarm_load_secrets() {
    local f line k v; f="$(swarm_secrets_file)"
    [ -f "$f" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|'#'*) continue ;; esac
        case "$line" in *=*) : ;; *) continue ;; esac
        k="${line%%=*}"; v="${line#*=}"
        # trim espacios alrededor de la clave
        k="${k#"${k%%[![:space:]]*}"}"; k="${k%"${k##*[![:space:]]}"}"
        # solo claves con nombre valido de variable (evita inyeccion via export)
        case "$k" in ''|[!A-Za-z_]*|*[!A-Za-z0-9_]*) continue ;; esac
        # trim espacios del valor + quitar comillas envolventes
        v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
        case "$v" in \"*\") v="${v#\"}"; v="${v%\"}" ;; \'*\') v="${v#\'}"; v="${v%\'}" ;; esac
        # no pisar si ya esta seteada en el entorno
        [ -n "${!k+x}" ] || export "$k=$v"
    done < "$f"
}

# ── Ramas largas de deploy (staging/producción, marker-based) ────────────────
# El modelo staging/prod se declara en workspace.md (markers STAGING_BRANCH / PROD_BRANCH,
# ver workspace.example.md § Deploy). Típico Odoo.sh: push a la rama larga = deploy del
# entorno. Vacío si el workspace no declara el marker (rige el modelo simple del skill `git`).

# Rama de staging/integración (ej. stagesunra). feature/fix nacen y apuntan acá.
swarm_staging_branch() { swarm_ws_marker STAGING_BRANCH; }

# Rama de producción (estable, desplegada; ej. main). hotfix nace acá; release apunta acá.
swarm_prod_branch() { swarm_ws_marker PROD_BRANCH; }

# Plataforma de deploy declarada (ej. odoo.sh) y URLs de los entornos. Informativos
# (/salud, /contexto, handoffs de @git-flow). Vacío si no se declaran.
swarm_deploy_platform() { swarm_ws_marker DEPLOY_PLATFORM; }
swarm_prod_url()        { swarm_ws_marker PROD_URL; }
swarm_staging_url()     { swarm_ws_marker STAGING_URL; }

# Resuelve una lista de tokens (handles o paths) a paths ABSOLUTOS, uno por linea.
# - token sin "/" que coincide con un marcador -> su valor (handle)
# - si no -> el token como path; relativo (no empieza con / ni ~) -> bajo el root
swarm_resolve_paths() {
    local tokens="$1" t val
    for t in $tokens; do
        [ -z "$t" ] && continue
        case "$t" in
            */*|/*|"~"*) val="$t" ;;                 # ya parece un path
            *) val="$(swarm_ws_marker "$t")"; [ -z "$val" ] && val="$t" ;;  # handle o path simple
        esac
        case "$val" in "~"*) val="$HOME${val#\~}" ;; esac
        case "$val" in
            /*) printf '%s\n' "$val" ;;
            *)  printf '%s\n' "$NOKEY_WS_ROOT/$val" ;;
        esac
    done
}

# Raices de core/enterprise (absolutas) a excluir. Origen, en orden:
#   CORE_ROOTS -> handles ODOO_CORE/ODOO_ENTERPRISE -> default "odoo enterprise".
swarm_core_roots() {
    local toks; toks="$(swarm_ws_marker CORE_ROOTS)"
    if [ -z "$toks" ]; then
        toks="$(swarm_ws_marker ODOO_CORE) $(swarm_ws_marker ODOO_ENTERPRISE)"
        toks="$(printf '%s' "$toks" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    fi
    [ -z "$toks" ] && toks="odoo enterprise"
    swarm_resolve_paths "$toks"
}

# Raices de addons custom (absolutas) = CLIENT_ADDONS + PRODUCT_ADDONS + ADDONS_ROOTS (legacy).
# Default/compat si no hay nada declarado: extra-addons/.
swarm_addons_roots() {
    local toks
    toks="$(swarm_ws_marker CLIENT_ADDONS) $(swarm_ws_marker PRODUCT_ADDONS) $(swarm_ws_marker ADDONS_ROOTS)"
    toks="$(printf '%s' "$toks" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/ /g')"
    [ -z "$toks" ] && toks="extra-addons"
    swarm_resolve_paths "$toks" | awk '!seen[$0]++'
}

# Raices de addons de cliente (absolutas). Para agentes/tareas que solo miran clientes.
swarm_client_addons() { swarm_resolve_paths "$(swarm_ws_marker CLIENT_ADDONS)"; }

# Raices de productos/repos compartidos (absolutas).
swarm_product_addons() { swarm_resolve_paths "$(swarm_ws_marker PRODUCT_ADDONS)"; }

# True (0) si el archivo esta bajo una raiz de core/enterprise — no se valida ni documenta.
swarm_is_core_path() {
    local file="$1" abs cr dir
    # Path absoluto. Si el dir padre existe, lo canonicalizamos (resuelve symlinks y ..);
    # si NO existe (ej. crear un archivo nuevo en core), resolvemos lexicamente para no
    # perder la deteccion — un cd fallido antes dejaba abs="/basename" y daba falso negativo.
    case "$file" in
        /*) abs="$file" ;;
        *)  abs="$PWD/$file" ;;
    esac
    dir="$(dirname "$abs")"
    [ -d "$dir" ] && abs="$(cd "$dir" && pwd)/$(basename "$abs")"
    while IFS= read -r cr; do
        [ -z "$cr" ] && continue
        case "$abs/" in "$cr"/*) return 0 ;; esac
    done < <(swarm_core_roots)
    return 1
}

# Echo de la raiz del modulo (carpeta con __manifest__.py) subiendo desde el archivo.
# Vacio si el archivo no pertenece a un modulo o si esta bajo core/enterprise.
swarm_module_root() {
    local file="$1" dir
    swarm_is_core_path "$file" && return 0
    dir="$(dirname "$file")"
    while [ "$dir" != "/" ] && [ "$dir" != "." ] && [ ! -f "$dir/__manifest__.py" ]; do
        dir="$(dirname "$dir")"
    done
    [ -f "$dir/__manifest__.py" ] && printf '%s' "$dir"
}

# Echo de la "raiz de repo" que agrupa modulos (para el indice README del repo).
# Recorre las raices de addons resueltas y, para el primer segmento bajo la que matchee:
#   - si ese segmento es un modulo (tiene __manifest__.py) -> la raiz de addons ES el repo
#   - si no -> el repo es <raiz>/<segmento>
swarm_repo_root() {
    local file="$1" base after segment candidate
    while IFS= read -r base; do
        [ -z "$base" ] && continue
        case "$file" in
            "$base"/*)
                after="${file#"$base"/}"; segment="${after%%/*}"
                candidate="$base/$segment"
                if [ -f "$candidate/__manifest__.py" ]; then
                    printf '%s' "$base"          # modulos directos bajo la raiz -> la raiz es el repo
                else
                    printf '%s' "$candidate"     # <raiz>/<repo>/<modulo> -> el repo es <raiz>/<repo>
                fi
                return 0 ;;
        esac
    done < <(swarm_addons_roots)
}

# ── Config por repo (.swarm.conf) ────────────────────────────────────────────
# Politicas compartidas del repo de addons: archivo .swarm.conf COMMITTEADO en la raiz
# del repo (formato KEY=value, como el de secretos; plantilla en assets/templates/).
# A diferencia de workspace.md (per-dev, gitignored), esto lo comparte todo el equipo.

# Lee una clave de <repo>/.swarm.conf. $2 puede ser cualquier path dentro del repo
# (se resuelve con swarm_repo_root) o la raiz misma del repo. Vacio si no hay archivo/clave.
swarm_repo_conf() {
    local key="$1" path="$2" repo conf
    repo="$(swarm_repo_root "$path")"
    [ -n "$repo" ] || { [ -f "$path/.swarm.conf" ] && repo="$path"; }
    [ -n "$repo" ] && conf="$repo/.swarm.conf" || return 0
    [ -f "$conf" ] || return 0
    grep -E "^[[:space:]]*${key}=" "$conf" 2>/dev/null \
        | head -1 \
        | sed -E "s/^[[:space:]]*${key}=[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//"
}

# True (0) si el repo del path declara TESTS=required en su .swarm.conf.
swarm_tests_required() {
    [ "$(swarm_repo_conf TESTS "$1")" = "required" ]
}

# True (0) si el modulo tiene tests reales: carpeta tests/ con al menos un test_*.py.
swarm_module_has_tests() {
    local module_dir="$1" f
    [ -n "$module_dir" ] && [ -d "$module_dir/tests" ] || return 1
    for f in "$module_dir"/tests/test_*.py; do
        [ -f "$f" ] && return 0
    done
    return 1
}

# True (0) si el repo del path declara E2E=required en su .swarm.conf (eje e2e, independiente
# de TESTS: un repo puede requerir backend, e2e, ambos o ninguno).
swarm_e2e_required() {
    [ "$(swarm_repo_conf E2E "$1")" = "required" ]
}

# True (0) si el modulo tiene un Tour de Odoo (test e2e de UI): un test que llama start_tour(),
# o un tour JS registrado en web_tour.tours bajo static/. Heuristica, best-effort.
swarm_module_has_e2e() {
    local module_dir="$1"
    [ -n "$module_dir" ] || return 1
    [ -d "$module_dir/tests" ] && grep -rlq "start_tour(" "$module_dir/tests" 2>/dev/null && return 0
    [ -d "$module_dir/static" ] && grep -rlq "web_tour.tours" "$module_dir/static" 2>/dev/null && return 0
    return 1
}

# True (0) si el modulo tiene una "superficie de UI" (senal para acotar el recordatorio e2e por
# juicio): tiene controllers/ (endpoints web) o JS propio bajo static/src. Un modulo backend puro
# (solo modelos + vistas backend) NO la tiene -> no se le pide e2e.
swarm_module_has_ui() {
    local module_dir="$1"
    [ -n "$module_dir" ] || return 1
    [ -d "$module_dir/controllers" ] && return 0
    [ -d "$module_dir/static/src" ] && find "$module_dir/static/src" -name "*.js" 2>/dev/null | grep -q . && return 0
    return 1
}

# Echo del path de la spec SDD de un modulo (un solo archivo bajo <module_dir>/specs/*.md).
# Convencion: una spec por modulo. Si hubiera varias (no deberia), devuelve la primera.
# Vacio si el modulo no tiene specs/.
swarm_module_spec() {
    local module_dir="$1" f
    [ -n "$module_dir" ] && [ -d "$module_dir/specs" ] || return 0
    for f in "$module_dir"/specs/*.md; do
        [ -f "$f" ] && { printf '%s' "$f"; return 0; }
    done
}

# Echo de la version declarada en __manifest__.py (campo 'version'). Vacio si no se puede leer.
swarm_manifest_version() {
    local module_dir="$1" manifest="$1/__manifest__.py"
    [ -f "$manifest" ] || return 0
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$manifest" <<'PY' 2>/dev/null
import ast, sys
try:
    d = ast.literal_eval(open(sys.argv[1], encoding="utf-8").read())
    print((d.get("version") or "").strip())
except Exception:
    pass
PY
    else
        grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$manifest" 2>/dev/null \
            | head -1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
    fi
}

# Echo de la version declarada en la spec (fila "| **Version** | `x.x.x` ... |"). Vacio si no hay.
# Tolera variantes reales: "**Version spec**", "**Versión**" (specs viejas pre-canon).
swarm_spec_version() {
    local spec="$1"
    [ -f "$spec" ] || return 0
    grep -iE '^\|[[:space:]]*\*\*Versi(o|ó)n( spec)?\*\*[[:space:]]*\|' "$spec" 2>/dev/null \
        | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# Directorios donde buscar archivos modificados (fallback sin args) = raices de addons.
swarm_addons_search_dirs() { swarm_addons_roots; }

# Cuenta de modulos (carpetas con __manifest__.py) bajo las raices de addons.
swarm_module_count() {
    local total=0 adir n
    while IFS= read -r adir; do
        [ -n "$adir" ] && [ -d "$adir" ] || continue
        n="$(find "$adir" -maxdepth 3 -name __manifest__.py 2>/dev/null | wc -l | tr -d ' ')"
        total=$((total + n))
    done < <(swarm_addons_roots)
    printf '%s' "$total"
}

# Motor de contenedores declarado en workspace.md (marcador ODOO_CONTAINER_ENGINE).
# NO se infiere el engine: se lee tal cual. Si no se declara, default 'docker'
# (compatibilidad). Un entorno venv no declara ODOO_CONTAINER, asi que esto solo
# aplica cuando hay un contenedor declarado.
swarm_container_engine() {
    local e; e="$(swarm_ws_marker ODOO_CONTAINER_ENGINE)"
    [ -n "$e" ] && printf '%s' "$e" || printf 'docker'
}

# Estado del contenedor de Odoo declarado en workspace.md (marcador ODOO_CONTAINER),
# consultado con el engine declarado (ODOO_CONTAINER_ENGINE: docker|podman).
# Echo: "up" si corre, "down" si esta declarado pero no corre, "n-a" si no hay
# marcador o el engine no esta disponible.
swarm_docker_status() {
    local c engine running; c="$(swarm_ws_marker ODOO_CONTAINER)"
    [ -n "$c" ] || { printf 'n-a'; return 0; }
    engine="$(swarm_container_engine)"
    command -v "$engine" >/dev/null 2>&1 || { printf 'n-a'; return 0; }
    running="$(timeout 5 "$engine" ps --filter "name=^/${c}$" --format '{{.Names}}' 2>/dev/null)"
    [ -n "$running" ] && printf 'up' || printf 'down'
}

# Linea compacta de orientacion: banner de SessionStart y header de /contexto.
# "Odoo <ver> · clientes: <a,b> · <engine> <up/down/n-a> · <N> modulos · enjambre <branch>"
# (el branch del cwd ya lo muestra el statusline en vivo; aca va el del repo del enjambre).
# Nivel de paralelizacion del orquestador (workspace.md PARALLELISM; default readonly).
swarm_parallelism() {
    local p; p="$(swarm_ws_marker PARALLELISM)"
    case "$p" in
        off|readonly|full) printf '%s' "$p" ;;
        *) printf 'readonly' ;;   # ausente o invalido -> default conservador
    esac
}

swarm_orientation_line() {
    local ver clients docker engine n_mods ebranch par
    ver="$(swarm_ws_marker ODOO_VERSION)"; [ -n "$ver" ] || ver="?"
    docker="$(swarm_docker_status)"
    engine="$(swarm_container_engine)"
    clients="$(swarm_client_addons | while IFS= read -r p; do [ -n "$p" ] && basename "$p"; done \
        | paste -sd, - 2>/dev/null)"
    [ -n "$clients" ] || clients="-"
    n_mods="$(swarm_module_count)"
    par="$(swarm_parallelism)"
    ebranch="$(git -C "$NOKEY_CLAUDE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    printf 'Odoo %s · clientes: %s · %s %s · %s modulos · parallelism %s' "$ver" "$clients" "$engine" "$docker" "$n_mods" "$par"
    [ -n "$ebranch" ] && printf ' · enjambre %s' "$ebranch"
}
