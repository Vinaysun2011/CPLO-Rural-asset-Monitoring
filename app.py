import io
import os
import threading
import time
from datetime import datetime
from decimal import Decimal
from functools import wraps

import pymysql
from dotenv import load_dotenv
from flask import Flask, jsonify, render_template, request, send_file, session
from openpyxl import Workbook
from openpyxl.cell import WriteOnlyCell
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

load_dotenv()

app = Flask(__name__)
app.secret_key = os.environ["SECRET_KEY"]
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=bool(os.environ.get("VERCEL")),  # https only when on Vercel
)

# ---- config (all from .env / Vercel settings, never hard-coded) ----
DB = dict(
    host=os.environ["DB_HOST"],
    port=int(os.environ.get("DB_PORT", "3306")),
    user=os.environ["DB_USER"],
    password=os.environ["DB_PASSWORD"],
    database=os.environ.get("DB_NAME", ""),
    connect_timeout=15,
    read_timeout=int(os.environ.get("QUERY_TIMEOUT", "120")),
    charset="utf8mb4",
)
CACHE_SECONDS = int(os.environ.get("CACHE_SECONDS", "60"))
SCREEN_ROW_LIMIT = int(os.environ.get("SCREEN_ROW_LIMIT", "1000"))  # rows shown on screen

# APP_USERS="client1:pass1,client2:pass2"
def _parse_users(raw):
    users = {}
    for line in raw.replace("\r", "").split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue  # skip blank lines and comment lines pasted from .env
        if line.upper().startswith("APP_USERS="):
            line = line.split("=", 1)[1]  # value pasted together with its name
        for pair in line.split(","):
            if ":" in pair:
                u, p = pair.split(":", 1)
                users[u.strip().strip("\"'")] = p.strip().strip("\"'")
    return users


USERS = _parse_users(os.environ.get("APP_USERS", ""))

with open(os.path.join(os.path.dirname(__file__), "report.sql"), encoding="utf-8") as f:
    SQL = f.read()

# The SQL returns one row per panchayat. Columns 0-4 are labels, the rest are numbers.
N_LABEL = 5
I_DISTRICT, I_BLOCK, I_PID, I_SURVEY = 0, 1, 3, 4
LEVELS = {
    "district": "District wise",
    "block": "Block wise",
    "panchayat": "Panchayat wise",
}

_cache = {"ts": 0, "data": None}
_lock = threading.Lock()


def _clean(v):
    if isinstance(v, Decimal):
        return int(v) if v == v.to_integral_value() else float(v)
    return v


def fetch_base(force=False):
    """Run the SQL once (read-only) and cache it briefly. District and block
    reports are calculated from these panchayat rows, so one query serves all."""
    with _lock:
        if not force and _cache["data"] and time.time() - _cache["ts"] < CACHE_SECONDS:
            return _cache["data"]
        conn = pymysql.connect(**DB)
        try:
            with conn.cursor() as cur:
                cur.execute(SQL)  # no args: '%' in the SQL is left untouched
                columns = [d[0] for d in cur.description]
                rows = [[_clean(v) for v in r] for r in cur.fetchall()]
        finally:
            conn.close()
        data = {
            "columns": columns,
            "rows": rows,
            "generated_at": datetime.now().strftime("%d-%b-%Y %H:%M:%S"),
        }
        _cache.update(ts=time.time(), data=data)
        return data


def _sort_key(key):
    return tuple("" if v is None else str(v).lower() for v in key)


def rollup(base, key_idx, key_names, rows):
    """Add up panchayat rows by district (or district+block)."""
    num_names = base["columns"][N_LABEL:]
    groups = {}
    for r in rows:
        key = tuple(r[i] for i in key_idx)
        g = groups.get(key)
        if g is None:
            g = groups[key] = {"ids": set(), "started": set(), "sums": [0] * len(num_names)}
        g["ids"].add(r[I_PID])
        if r[I_SURVEY] == "Yes":
            g["started"].add(r[I_PID])
        for j, v in enumerate(r[N_LABEL:]):
            g["sums"][j] += v or 0
    out = []
    for key in sorted(groups, key=_sort_key):
        g = groups[key]
        total, started = len(g["ids"]), len(g["started"])
        pct = round(started / total * 100, 1) if total else 0
        out.append(list(key) + [total, started, total - started, pct] + g["sums"])
    columns = list(key_names) + [
        "Total_panchayats",
        "GPs_Survey_Started",
        "GPs_Survey_Not_Started",
        "%age of GPs (Survey Started)",
    ] + num_names
    return columns, out


def build_total(columns, rows, n_label):
    """Total row: adds every number column, recomputes the % column."""
    tot = ["Total"] + [""] * (n_label - 1)
    for i in range(n_label, len(columns)):
        tot.append(sum((r[i] or 0) for r in rows if isinstance(r[i], (int, float))))
    for i, c in enumerate(columns):
        if c.startswith("%age"):
            t = tot[columns.index("Total_panchayats")]
            s = tot[columns.index("GPs_Survey_Started")]
            tot[i] = round(s / t * 100, 1) if t else 0
    return tot


def get_level(level, district=None, block=None, force=False):
    """Returns columns, rows, total, n_label for one report level."""
    base = fetch_base(force)
    rows = base["rows"]
    if district:
        rows = [r for r in rows if r[I_DISTRICT] == district]
    if block:
        rows = [r for r in rows if r[I_BLOCK] == block]
    if level == "district":
        columns, out = rollup(base, [I_DISTRICT], ["District"], rows)
        n_label = 1
    elif level == "block":
        columns, out = rollup(base, [I_DISTRICT, I_BLOCK], ["District", "Block_name"], rows)
        n_label = 2
    else:
        columns, out, n_label = base["columns"], rows, N_LABEL
    total = build_total(columns, out, n_label)
    if level == "panchayat":  # show number of panchayats that started the survey
        total[I_SURVEY] = f"{sum(1 for r in out if r[I_SURVEY] == 'Yes')} Yes"
    return columns, out, total, n_label, base["generated_at"]


def login_required(fn):
    @wraps(fn)
    def wrapper(*a, **kw):
        if not session.get("user"):
            return jsonify(error="Not logged in"), 401
        return fn(*a, **kw)
    return wrapper


@app.get("/")
def index():
    return render_template("index.html")


@app.post("/api/login")
def login():
    body = request.get_json(silent=True) or {}
    u, p = body.get("username", ""), body.get("password", "")
    if u in USERS and USERS[u] == p:
        session["user"] = u
        return jsonify(ok=True)
    return jsonify(error="Wrong username or password"), 401


@app.post("/api/logout")
def logout():
    session.clear()
    return jsonify(ok=True)


@app.get("/api/me")
def me():
    return jsonify(user=session.get("user"))


def _args():
    level = request.args.get("level", "district")
    if level not in LEVELS and level != "all":
        level = "district"
    return (
        level,
        request.args.get("district") or None,
        request.args.get("block") or None,
        request.args.get("fresh") == "1",
    )


@app.get("/api/report")
@login_required
def report():
    level, district, block, fresh = _args()
    try:
        columns, rows, total, n_label, gen = get_level(
            level if level != "all" else "district", district, block, fresh
        )
        base = fetch_base()
    except Exception as e:  # show a readable message, not a stack trace
        return jsonify(error=f"Could not read the database: {e}"), 500
    # drop-down choices
    blocks = {}
    for r in base["rows"]:
        blocks.setdefault(r[I_DISTRICT], set()).add(r[I_BLOCK])
    filters = {
        "districts": sorted((d for d in blocks if d is not None), key=str.lower),
        "blocks": {d: sorted((b for b in bs if b is not None), key=str.lower)
                   for d, bs in blocks.items() if d is not None},
    }
    shown = rows[:SCREEN_ROW_LIMIT]
    return jsonify(
        columns=columns,
        rows=shown,
        total=total,
        n_label=n_label,
        row_count=len(rows),
        truncated=len(rows) > len(shown),
        generated_at=gen,
        filters=filters,
    )


def _write_sheet(wb, title, columns, rows, total, n_label, gen):
    ws = wb.create_sheet(title)
    big = len(rows) > 5000  # keep large sheets light so the file builds quickly
    thin = Side(style="thin", color="BBBBBB")
    border = Border(left=thin, right=thin, top=thin, bottom=thin)
    head_font = Font(bold=True, color="FFFFFF")
    head_fill = PatternFill("solid", fgColor="1F4E78")
    tot_font = Font(bold=True)
    tot_fill = PatternFill("solid", fgColor="DDEBF7")

    for i in range(1, len(columns) + 1):
        ws.column_dimensions[get_column_letter(i)].width = 24 if i <= n_label else 16
    ws.freeze_panes = f"{get_column_letter(n_label + 1)}4"

    ws.append([f"{title} - report generated: {gen}"])
    ws.append([])

    hdr = []
    for c in columns:
        cell = WriteOnlyCell(ws, value=c)
        cell.font, cell.fill, cell.border = head_font, head_fill, border
        cell.alignment = Alignment(wrap_text=True, vertical="center", horizontal="center")
        hdr.append(cell)
    ws.append(hdr)

    for r in rows:
        if big:
            ws.append(r)
            continue
        line = []
        for ci, v in enumerate(r):
            cell = WriteOnlyCell(ws, value=v)
            cell.border = border
            if columns[ci] == "PanchayatId":
                pass  # an ID, not a quantity: no thousands separator
            elif isinstance(v, (int, float)) and not isinstance(v, bool):
                cell.number_format = "#,##0.0" if isinstance(v, float) else "#,##0"
            line.append(cell)
        ws.append(line)

    line = []
    for v in total:
        cell = WriteOnlyCell(ws, value=v)
        cell.font, cell.fill, cell.border = tot_font, tot_fill, border
        if isinstance(v, (int, float)):
            cell.number_format = "#,##0.0" if isinstance(v, float) else "#,##0"
        line.append(cell)
    ws.append(line)


@app.get("/api/report.xlsx")
@login_required
def report_xlsx():
    level, district, block, fresh = _args()
    levels = list(LEVELS) if level == "all" else [level]
    wb = Workbook(write_only=True)
    try:
        for i, lv in enumerate(levels):
            columns, rows, total, n_label, gen = get_level(lv, district, block, fresh and i == 0)
            _write_sheet(wb, LEVELS[lv], columns, rows, total, n_label, gen)
    except Exception as e:
        return jsonify(error=f"Could not read the database: {e}"), 500

    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    part = "all_levels" if level == "all" else level
    name = f"report_{part}_{datetime.now().strftime('%Y%m%d_%H%M')}.xlsx"
    return send_file(
        buf,
        as_attachment=True,
        download_name=name,
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )


if __name__ == "__main__":
    # Local use only. On Vercel the `app` object above is served directly.
    port = int(os.environ.get("PORT", "5000"))
    print(f"Running on http://localhost:{port}")
    try:
        from waitress import serve
        serve(app, host="0.0.0.0", port=port, threads=8)
    except ImportError:
        app.run(host="0.0.0.0", port=port)
