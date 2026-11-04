#!/usr/bin/env bash
# Rootless process controller for Sherlock on shared hosting.
set -Eeuo pipefail

APP_DIR="${SHERLOCK_HOME:-$HOME/.local/opt/sherlock}"
STATE_DIR="${SHERLOCK_STATE_DIR:-$HOME/.local/var/sherlock-feral}"
ENV_FILE="${SHERLOCK_ENV_FILE:-$HOME/.config/sherlock-feral/sherlock.env}"
RUNTIME_PREFIX="${SHERLOCK_RUNTIME_PREFIX:-$HOME/.local/opt/sherlock-runtime}"
NODE_BIN="$RUNTIME_PREFIX/node/node-v22.21.1-linux-x64-glibc-217/bin"
PID_FILE="$STATE_DIR/puma.pid"
LOG_FILE="$STATE_DIR/puma.log"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
mkdir -p "$STATE_DIR"
[[ -d "$APP_DIR" ]] || die "Application directory not found: $APP_DIR"
[[ -f "$ENV_FILE" ]] || die "Environment file not found: $ENV_FILE"

# The installer writes shell-escaped KEY=value entries and chmods this file 0600.
[[ "$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE")" == 600 ]] ||
  die "Environment file must have mode 0600: $ENV_FILE"

load_env() {
  export PATH="$RUNTIME_PREFIX/bin:$NODE_BIN:$PATH"
  export LD_LIBRARY_PATH="$RUNTIME_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export BUNDLE_APP_CONFIG="$HOME/.config/sherlock-feral/bundle"
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
}

read_pid() {
  [[ -s "$PID_FILE" ]] || return 1
  local pid
  IFS= read -r pid < "$PID_FILE" || true
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$pid"
}

is_running() {
  local pid
  pid="$(read_pid)" || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  # Avoid signalling an unrelated process if a stale PID file was reused.
  local cmd
  cmd="$(ps -p "$pid" -o args= 2>/dev/null || true)"
  [[ "$cmd" == *puma* || "$cmd" == *"rails server"* ]]
}

start() {
  if is_running; then echo "Sherlock is already running (PID $(read_pid))."; return 0; fi
  rm -f "$PID_FILE"
  load_env
  cd "$APP_DIR"
  export RAILS_ENV=production
  export RAILS_LOG_TO_STDOUT=true
  export SOLID_QUEUE_IN_PUMA=true
  export PIDFILE="$PID_FILE"
  export PORT="${PORT:-18443}"
  export BINDING="${BINDING:-127.0.0.1}"
  nohup bundle exec puma -C deploy/feral/puma.rb >>"$LOG_FILE" 2>&1 </dev/null &
  local pid=$!
  printf '%s\n' "$pid" > "$PID_FILE"
  chmod 600 "$PID_FILE"
  for _ in $(seq 1 30); do
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$PID_FILE"
      die "Puma exited during startup. Inspect $LOG_FILE"
    fi
    if command -v curl >/dev/null 2>&1 && curl -fsS "http://$BINDING:$PORT/up" >/dev/null 2>&1; then
      echo "Sherlock started (PID $pid) on $BINDING:$PORT"
      return 0
    fi
    sleep 1
  done
  echo "Puma process started (PID $pid), but health check did not pass within 30 seconds."
  echo "Inspect $LOG_FILE and verify database connectivity."
  return 1
}

stop() {
  if ! is_running; then rm -f "$PID_FILE"; echo "Sherlock is not running."; return 0; fi
  local pid
  pid="$(read_pid)"
  kill -TERM "$pid"
  for _ in $(seq 1 30); do
    kill -0 "$pid" 2>/dev/null || { rm -f "$PID_FILE"; echo "Sherlock stopped."; return 0; }
    sleep 1
  done
  echo "Graceful stop timed out; sending KILL to PID $pid." >&2
  kill -KILL "$pid" 2>/dev/null || true
  rm -f "$PID_FILE"
}

status() {
  if is_running; then echo "RUNNING (PID $(read_pid))"; else echo "STOPPED"; return 1; fi
}

logs() { touch "$LOG_FILE"; tail -n 100 -f "$LOG_FILE"; }

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  status) status ;;
  logs) logs ;;
  *) echo "Usage: $0 {start|stop|restart|status|logs}" >&2; exit 2 ;;
esac
