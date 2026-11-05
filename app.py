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

# ---- config (all from .env, never hard-coded) ----
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

# APP_USERS="client1:pass1,client2:pass2"
USERS = dict(
    pair.split(":", 1) for pair in os.environ.get("APP_USERS", "").split(",") if ":" in pair
)

with open(os.path.join(os.path.dirname(__file__), "report.sql"), encoding="utf-8") as f:
    SQL = f.read()

_cache = {"ts": 0, "data": None}
_lock = threading.Lock()


def _clean(v):
    if isinstance(v, Decimal):
        return int(v) if v == v.to_integral_value() else float(v)
    return v


def fetch_report(force=False):
    """Run the SQL (read-only) and return the rows. Cached briefly so many
    clients opening the page do not hammer the database."""
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
        data["totals"] = build_totals(columns, rows)
        _cache.update(ts=time.time(), data=data)
        return data


def build_totals(columns, rows):
    totals = ["Total"]
    for i in range(1, len(columns)):
        vals = [r[i] for r in rows]
        if all(isinstance(v, (int, float)) or v is None for v in vals):
            totals.append(sum(v or 0 for v in vals))
        else:
            totals.append("")
    # recompute the percentage column from the totals
    try:
        pct_i = next(i for i, c in enumerate(columns) if c.startswith("%age"))
        tot_i = columns.index("Total_panchayats")
        not_i = columns.index("GPs_who_Not_Uploaded_any_assets")
        if totals[tot_i]:
            totals[pct_i] = f"{round((totals[tot_i] - totals[not_i]) / totals[tot_i] * 100, 1)}%"
    except (StopIteration, ValueError):
        pass
    return totals


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


@app.get("/api/report")
@login_required
def report():
    try:
        return jsonify(fetch_report(force=request.args.get("fresh") == "1"))
    except Exception as e:  # show a readable message, not a stack trace
        return jsonify(error=f"Could not read the database: {e}"), 500


@app.get("/api/report.xlsx")
@login_required
def report_xlsx():
    try:
        data = fetch_report(force=request.args.get("fresh") == "1")
    except Exception as e:
        return jsonify(error=f"Could not read the database: {e}"), 500

    wb = Workbook()
    ws = wb.active
    ws.title = "Report"
    ws.append([f"Report generated: {data['generated_at']}"])
    ws["A1"].font = Font(italic=True)
    ws.append([])
    ws.append(data["columns"])

    thin = Side(style="thin", color="BBBBBB")
    border = Border(left=thin, right=thin, top=thin, bottom=thin)
    for c in ws[3]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = PatternFill("solid", fgColor="1F4E78")
        c.alignment = Alignment(wrap_text=True, vertical="center", horizontal="center")
        c.border = border
    ws.row_dimensions[3].height = 48

    for r in data["rows"]:
        ws.append(r)
    ws.append(data["totals"])
    for c in ws[ws.max_row]:
        c.font = Font(bold=True)
        c.fill = PatternFill("solid", fgColor="DDEBF7")

    for row in ws.iter_rows(min_row=4, max_row=ws.max_row):
        for c in row:
            c.border = border
            if isinstance(c.value, (int, float)):
                c.number_format = "#,##0"
    for i, col in enumerate(data["columns"], start=1):
        ws.column_dimensions[get_column_letter(i)].width = 22 if i == 1 else 16
    ws.freeze_panes = "B4"

    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    name = f"report_{datetime.now().strftime('%Y%m%d_%H%M')}.xlsx"
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
