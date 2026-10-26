#!/usr/bin/env bash
# Started by the VM service from the release folder: run the app in the foreground on $PORT
# ($PORT_2 / $PORT_3 are also set if the admin assigned them). See README.md Part B for full recipes.
# Examples (replace the last two lines with one of these):
#   exec python3 -m http.server "$PORT" --bind 0.0.0.0 --directory site          # Static HTML
#   exec node_modules/.bin/vite preview --host 0.0.0.0 --port "$PORT" --strictPort  # React (Vite)
#   exec node server.js                                                          # Node.js (process.env.PORT)
#   exec .venv/bin/gunicorn -b "0.0.0.0:$PORT" app:app                           # Flask
#   exec .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port "$PORT"            # FastAPI
#   exec .venv/bin/gunicorn -b "0.0.0.0:$PORT" mysite.wsgi                       # Django
echo "Edit .cicd/start.sh to start your app on port \$PORT." >&2
exit 1
