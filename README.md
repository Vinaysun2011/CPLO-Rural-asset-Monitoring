# Asset Report App

A small web app: clients open a link, sign in, see the report with live data, and download it as Excel.
Only this app talks to the database, so clients never get database access or credentials.

## Files
- `app.py` - backend (runs your SQL, builds the Excel file, login)
- `report.sql` - your report query (edit this to change the report)
- `templates/index.html` - the report page
- `.env` - your private settings (created from `.env.example`)

## Run on your PC
1. Install Python 3.10+ from python.org.
2. Open a terminal in this folder and run:
   ```
   pip install -r requirements.txt
   ```
3. Copy `.env.example` to `.env` and fill in the database details, `SECRET_KEY` and `APP_USERS`.
4. Start it:
   ```
   python app.py
   ```
5. Open http://localhost:5000 and sign in.

## Share with clients (while your PC is on)
Install Cloudflare Tunnel (`cloudflared`) and run:
```
cloudflared tunnel --url http://localhost:5000
```
It prints a public https link. Send that link plus a username/password from `APP_USERS`.
The link stops working when you close the tunnel or switch off the PC.

## Always-on option
Deploy the same folder to Render, Railway or a small VPS, set the values from `.env` as
environment variables there, and use `python app.py` as the start command.
Your database must allow connections from that host's IP address.

## What the portal shows
Three tabs: **District wise**, **Block wise**, **Panchayat wise**. Pick a district / block to narrow the view.
- `report.sql` is the panchayat-wise query (one row per panchayat). Block and district totals are
  added up from those rows, so one database query feeds all three levels.
- **Download Excel (this tab)** gives the current level; **Download Excel (all 3 levels)** gives one file
  with three sheets. Filters apply to both. The Excel file always has every row; the screen shows the
  first 1,000 panchayats (set `SCREEN_ROW_LIMIT` to change).
- `report_original_panchayat.sql` is your original query; `old_queries/` holds the earlier district query.
- `suggested_indexes.sql` lists indexes that make the query faster (ask your DBA to run them).

## Notes
- Every "Generate / Refresh" click runs the SQL live. Results are reused for `CACHE_SECONDS`
  (default 60) so many users don't overload the database.
- Use a read-only database user. Never put credentials in the HTML or share the `.env` file.
- Use strong passwords in `APP_USERS`. Share the link only with people who should see this data.

## Deploy on Vercel
1. Put this folder in a GitHub repository (the `.env` file is ignored, do not upload it).
2. On vercel.com choose Add New > Project, import the repository. Framework is detected as Flask.
3. Before deploying, open Settings > Environment Variables and add: `DB_HOST`, `DB_PORT`, `DB_USER`,
   `DB_PASSWORD`, `DB_NAME`, `SECRET_KEY`, `APP_USERS` (and optionally `CACHE_SECONDS`, `QUERY_TIMEOUT`).
4. Deploy. Your link will look like `https://your-project.vercel.app`.

Or with the CLI: `npm i -g vercel`, then `vercel` in this folder, then add the variables and run `vercel --prod`.

Important: Vercel has no fixed IP address, so the database firewall must accept connections from any IP.
Use a read-only user with a strong password, and enable SSL on the database if it supports it.
