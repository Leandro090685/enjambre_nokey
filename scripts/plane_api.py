#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# scripts/plane_api.py — cliente de la API de Plane.so para el seguimiento del proyecto.
#
# La CONFIG llega por ENTORNO (la resuelve plane.sh desde workspace.md + el archivo de
# secretos): PLANE_API_BASE, PLANE_WORKSPACE, PLANE_PROJECT, PLANE_API_KEY. No se
# hardcodea nada: sin config, sale con error claro. Solo stdlib (urllib) — sin dependencias.
#
# Subcomandos: env, states, labels, members, list, next, get, create, update, move, comment, delete.
import argparse
import html
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("PLANE_API_BASE", "https://api.plane.so/api/v1").rstrip("/")
WS = os.environ.get("PLANE_WORKSPACE", "").strip()
PROJ = os.environ.get("PLANE_PROJECT", "").strip()
KEY = os.environ.get("PLANE_API_KEY", "").strip()
# Cloudflare (frente de api.plane.so) rechaza el User-Agent por defecto de urllib
# (Python-urllib/x.y) con "error code: 1010". Mandamos uno explícito y overridable.
USER_AGENT = os.environ.get("PLANE_USER_AGENT", "nokey-enjambre-plane/1.0")

UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
PRIORITIES = ("urgent", "high", "medium", "low", "none")
# Orden para elegir "la próxima" tarea: mayor urgencia primero; a igual prioridad, el issue más viejo.
PRIORITY_ORDER = {"urgent": 0, "high": 1, "medium": 2, "low": 3, "none": 4}

_states_cache = None
_labels_cache = None


def die(msg, code=1):
    print("ERROR: %s" % msg, file=sys.stderr)
    sys.exit(code)


def require_config(need_key=True):
    # Valida que estén los markers/secreto necesarios antes de pegarle a la API.
    missing = []
    if not WS:
        missing.append("PLANE_WORKSPACE")
    if not PROJ:
        missing.append("PLANE_PROJECT")
    if need_key and not KEY:
        missing.append("PLANE_API_KEY")
    if missing:
        die("falta configuración: %s\n"
            "  · PLANE_WORKSPACE / PLANE_PROJECT / PLANE_API_BASE → markers en .claude/workspace.md\n"
            "  · PLANE_API_KEY → archivo de secretos (NOKEY_SECRETS_FILE), formato KEY=value"
            % ", ".join(missing))


def api_url(path):
    return "%s/workspaces/%s/projects/%s/%s" % (BASE, WS, PROJ, path.lstrip("/"))


def request(method, path, body=None):
    url = api_url(path)
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("X-API-Key", KEY)
    req.add_header("User-Agent", USER_AGENT)
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = {"detail": raw[:500]}
        return e.code, parsed
    except urllib.error.URLError as e:
        die("no se pudo conectar a %s: %s" % (BASE, getattr(e, "reason", e)))


def paginate(path):
    # Plane usa cursor pagination: {results, next_page_results, next_cursor}.
    items = []
    cursor = None
    while True:
        p = path
        if cursor:
            sep = "&" if "?" in path else "?"
            p = "%s%scursor=%s" % (path, sep, urllib.parse.quote(str(cursor)))
        st, d = request("GET", p)
        if st >= 400:
            die("GET %s → HTTP %s: %s" % (path, st, json.dumps(d)[:300]))
        if isinstance(d, list):
            items.extend(d)
            break
        items.extend(d.get("results", []) or [])
        if d.get("next_page_results") and d.get("next_cursor"):
            cursor = d["next_cursor"]
        else:
            break
    return items


def states():
    global _states_cache
    if _states_cache is None:
        _states_cache = paginate("states/")
    return _states_cache


def state_id(name):
    for s in states():
        if (s.get("name") or "").lower() == name.lower():
            return s["id"]
    die("estado '%s' inexistente. Disponibles: %s"
        % (name, ", ".join(s.get("name", "?") for s in states())))


def state_name(sid):
    for s in states():
        if s.get("id") == sid:
            return s.get("name", "?")
    return "?"


def labels():
    global _labels_cache
    if _labels_cache is None:
        _labels_cache = paginate("labels/")
    return _labels_cache


def label_ids(names):
    ids = []
    have = {(l.get("name") or "").lower(): l["id"] for l in labels()}
    for n in names:
        lid = have.get(n.lower())
        if not lid:
            die("label '%s' inexistente. Disponibles: %s" % (n, ", ".join(have.keys()) or "(ninguna)"))
        ids.append(lid)
    return ids


def member_id(ref):
    # Acepta el UUID del miembro o (substring de) su display_name/email, case-insensitive.
    ref = str(ref).strip()
    if UUID_RE.match(ref):
        return ref
    matches = []
    for m in paginate("members/"):
        name = "%s %s" % (m.get("display_name") or "", m.get("email") or "")
        if ref.lower() in name.lower():
            matches.append((m.get("member") or m.get("id"), name.strip()))
    if not matches:
        die("miembro '%s' inexistente (ver `plane.sh members`)" % ref)
    if len(matches) > 1:
        die("miembro '%s' ambiguo: %s" % (ref, ", ".join(n for _, n in matches)))
    return matches[0][0]


def resolve_issue(ref):
    # Acepta el UUID del issue o su #número de secuencia (busca por sequence_id).
    ref = str(ref).strip()
    if UUID_RE.match(ref):
        return ref
    try:
        seq = int(ref.lstrip("#"))
    except ValueError:
        die("referencia inválida '%s' (usá #número o el UUID del issue)" % ref)
    for i in paginate("issues/"):
        if i.get("sequence_id") == seq:
            return i["id"]
    die("no encontré el issue #%s en el proyecto" % seq)


def to_html(text):
    # Si ya parece HTML lo deja; si es texto plano lo envuelve en <p> escapado.
    if text is None:
        return None
    if "<" in text and ">" in text:
        return text
    return "<p>%s</p>" % html.escape(text)


def issue_web_url(issue_id):
    return "https://app.plane.so/%s/projects/%s/issues/%s/" % (WS, PROJ, issue_id)


def check_priority(p):
    if p and p not in PRIORITIES:
        die("prioridad inválida '%s' (usá: %s)" % (p, ", ".join(PRIORITIES)))


# ── subcomandos ───────────────────────────────────────────────────────────────
def cmd_env(args):
    require_config(need_key=False)
    masked = (KEY[:10] + "…" + KEY[-4:]) if len(KEY) > 16 else ("(set)" if KEY else "(FALTA)")
    print("PLANE_API_BASE   %s" % BASE)
    print("PLANE_WORKSPACE  %s" % WS)
    print("PLANE_PROJECT    %s" % PROJ)
    print("PLANE_API_KEY    %s" % masked)
    if KEY:
        st, d = request("GET", "states/")
        print("conexión         HTTP %s%s" % (st, "" if st < 400 else " — " + json.dumps(d)[:200]))


def cmd_states(args):
    require_config()
    for s in sorted(states(), key=lambda x: x.get("sequence", 0)):
        print("%-38s  %-12s  %s" % (s["id"], s.get("group", ""), s.get("name", "")))


def cmd_labels(args):
    require_config()
    ls = labels()
    if not ls:
        print("(sin labels)")
    for l in ls:
        print("%-38s  %s" % (l["id"], l.get("name", "")))


def cmd_members(args):
    require_config()
    for m in paginate("members/"):
        name = m.get("display_name") or m.get("email") or m.get("member") or "?"
        print("%-38s  %s" % (m.get("member") or m.get("id", "?"), name))


def filter_issues(issues, state=None, priority=None, search=None, assignee=None):
    want_state = state.lower() if state else None
    want_prio = priority.lower() if priority else None
    q = search.lower() if search else None
    mid = member_id(assignee) if assignee else None
    out = []
    for i in issues:
        if want_state and state_name(i.get("state")).lower() != want_state:
            continue
        if want_prio and (i.get("priority") or "none").lower() != want_prio:
            continue
        if q and q not in (i.get("name") or "").lower():
            continue
        if mid and mid not in (i.get("assignees") or []):
            continue
        out.append(i)
    return out


def print_issue(i):
    print("#%s  %s" % (i.get("sequence_id"), i.get("name")))
    print("estado:    %s" % state_name(i.get("state")))
    print("prioridad: %s" % (i.get("priority") or "none"))
    print("id:        %s" % i.get("id"))
    print("url:       %s" % issue_web_url(i.get("id")))
    desc = i.get("description_html") or ""
    if desc:
        print("---\n%s" % desc)


def cmd_list(args):
    require_config()
    issues = filter_issues(paginate("issues/"), args.state, args.priority, args.search, args.assignee)
    rows = [(i.get("sequence_id"), state_name(i.get("state")), i.get("priority") or "none",
             i.get("name") or "") for i in sorted(issues, key=lambda x: x.get("sequence_id", 0))]
    if args.limit:
        rows = rows[: args.limit]
    for seq, sn, pr, nm in rows:
        print("#%-4s  %-12s  %-7s  %s" % (seq, sn, pr, nm))
    print("— %s issue(s)" % len(rows))


def cmd_next(args):
    # "La próxima tarea": el issue más urgente (y a igual prioridad, más viejo) del estado
    # dado (default Todo). Imprime el detalle completo para que el orquestador arranque directo.
    require_config()
    issues = filter_issues(paginate("issues/"), args.state or "Todo", None, None, args.assignee)
    if not issues:
        print("(sin tareas en estado '%s')" % (args.state or "Todo"))
        return
    issues.sort(key=lambda i: (PRIORITY_ORDER.get((i.get("priority") or "none").lower(), 9),
                               i.get("sequence_id") or 0))
    print_issue(issues[0])


def cmd_get(args):
    require_config()
    iid = resolve_issue(args.ref)
    st, i = request("GET", "issues/%s/" % iid)
    if st >= 400:
        die("HTTP %s: %s" % (st, json.dumps(i)[:300]))
    print_issue(i)


def cmd_create(args):
    require_config()
    check_priority(args.priority)
    body = {"name": args.name}
    if args.desc:
        body["description_html"] = to_html(args.desc)
    if args.state:
        body["state"] = state_id(args.state)
    if args.priority:
        body["priority"] = args.priority
    if args.label:
        body["labels"] = label_ids(args.label)
    if args.assignee:
        body["assignees"] = args.assignee
    st, d = request("POST", "issues/", body)
    if st >= 400 or not d.get("id"):
        die("no se pudo crear: HTTP %s — %s" % (st, json.dumps(d)[:300]))
    print("creada #%s — %s" % (d.get("sequence_id"), d.get("name")))
    print(issue_web_url(d["id"]))


def cmd_update(args):
    require_config()
    check_priority(args.priority)
    iid = resolve_issue(args.ref)
    body = {}
    if args.name:
        body["name"] = args.name
    if args.desc:
        body["description_html"] = to_html(args.desc)
    if args.state:
        body["state"] = state_id(args.state)
    if args.priority:
        body["priority"] = args.priority
    if args.label:
        body["labels"] = label_ids(args.label)
    if args.assignee:
        body["assignees"] = [member_id(a) for a in args.assignee]
    if not body:
        die("nada para actualizar (pasá --name/--desc/--state/--priority/--label/--assignee)")
    st, d = request("PATCH", "issues/%s/" % iid, body)
    if st >= 400:
        die("no se pudo actualizar: HTTP %s — %s" % (st, json.dumps(d)[:300]))
    print("actualizada #%s — %s" % (d.get("sequence_id"), d.get("name")))


def cmd_move(args):
    require_config()
    iid = resolve_issue(args.ref)
    st, d = request("PATCH", "issues/%s/" % iid, {"state": state_id(args.state)})
    if st >= 400:
        die("no se pudo mover: HTTP %s — %s" % (st, json.dumps(d)[:300]))
    print("#%s → %s" % (d.get("sequence_id"), state_name(d.get("state"))))


def cmd_comment(args):
    require_config()
    iid = resolve_issue(args.ref)
    st, d = request("POST", "issues/%s/comments/" % iid, {"comment_html": to_html(args.text)})
    if st >= 400:
        die("no se pudo comentar: HTTP %s — %s" % (st, json.dumps(d)[:300]))
    print("comentario agregado a #%s" % str(args.ref).lstrip("#"))


def cmd_delete(args):
    require_config()
    if not args.yes:
        die("borrado destructivo: repetí con --yes para confirmar")
    iid = resolve_issue(args.ref)
    st, d = request("DELETE", "issues/%s/" % iid)
    if st >= 400:
        die("no se pudo borrar: HTTP %s — %s" % (st, json.dumps(d)[:300]))
    print("borrada %s (HTTP %s)" % (args.ref, st))


def build_parser():
    p = argparse.ArgumentParser(prog="plane", description="Seguimiento del proyecto en Plane.so")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("env", help="mostrar config resuelta y probar conexión").set_defaults(fn=cmd_env)
    sub.add_parser("states", help="listar estados").set_defaults(fn=cmd_states)
    sub.add_parser("labels", help="listar labels").set_defaults(fn=cmd_labels)
    sub.add_parser("members", help="listar miembros del proyecto").set_defaults(fn=cmd_members)

    sp = sub.add_parser("list", help="listar issues")
    sp.add_argument("--state")
    sp.add_argument("--priority")
    sp.add_argument("--search")
    sp.add_argument("--assignee", help="UUID o nombre del miembro")
    sp.add_argument("--limit", type=int)
    sp.set_defaults(fn=cmd_list)

    sp = sub.add_parser("next", help="la próxima tarea a tomar (más urgente de Todo)")
    sp.add_argument("--state", help="estado del pool (default: Todo)")
    sp.add_argument("--assignee", help="limitar a un miembro (UUID o nombre)")
    sp.set_defaults(fn=cmd_next)

    sp = sub.add_parser("get", help="ver un issue")
    sp.add_argument("ref")
    sp.set_defaults(fn=cmd_get)

    sp = sub.add_parser("create", help="crear issue")
    sp.add_argument("--name", required=True)
    sp.add_argument("--desc")
    sp.add_argument("--state")
    sp.add_argument("--priority")
    sp.add_argument("--label", action="append")
    sp.add_argument("--assignee", action="append")
    sp.set_defaults(fn=cmd_create)

    sp = sub.add_parser("update", help="editar issue")
    sp.add_argument("ref")
    sp.add_argument("--name")
    sp.add_argument("--desc")
    sp.add_argument("--state")
    sp.add_argument("--priority")
    sp.add_argument("--label", action="append")
    sp.add_argument("--assignee", action="append", help="UUID o nombre (reemplaza los assignees)")
    sp.set_defaults(fn=cmd_update)

    sp = sub.add_parser("move", help="cambiar el estado de un issue")
    sp.add_argument("ref")
    sp.add_argument("state")
    sp.set_defaults(fn=cmd_move)

    sp = sub.add_parser("comment", help="comentar un issue")
    sp.add_argument("ref")
    sp.add_argument("text")
    sp.set_defaults(fn=cmd_comment)

    sp = sub.add_parser("delete", help="borrar un issue (requiere --yes)")
    sp.add_argument("ref")
    sp.add_argument("--yes", action="store_true")
    sp.set_defaults(fn=cmd_delete)

    return p


def main():
    args = build_parser().parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
