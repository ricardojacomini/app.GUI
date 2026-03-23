#!/bin/bash 
set +m

export host
export port
export DISPLAY
export WEBSOCKIFY_CMD="websockify"

function lmd()
{
  unset MODULES_CMD
  source /data/apps/helpers/Lmod
  source /data/apps/helpers/singularity.sh > /dev/null 2>&1
}

lmd

MODE="launch"
GEOMETRY="${APP_GUI_GEOMETRY:-}"
case "${1:-}" in
  --geometry)
    if [[ $# -lt 2 ]]; then
      echo "Missing value for --geometry" 1>&2
      exit 1
    fi
    GEOMETRY="$2"
    shift 2
    ;;&
  ""|"--start-session"|"--session-only")
    MODE="start-session"
    [[ $# -gt 0 ]] && shift
    ;;
  "--print-env")
    MODE="print-env"
    shift
    ;;
  "--help"|"-h")
    cat 1>&2 <<'END_HELP'
Internal launcher for app.GUI.
Use the unified interface instead:
  app --help
END_HELP
    exit 0
    ;;
esac

BACKEND="gpu"
SESSION_ROOT="${HOME}/.app.GUI/${BACKEND}"
ACTIVE_SESSION_FILE="${SESSION_ROOT}/current"
mkdir -p "${SESSION_ROOT}"

get_active_session_dir() {
  [[ -f "${ACTIVE_SESSION_FILE}" ]] && cat "${ACTIVE_SESSION_FILE}"
}

if [[ "${MODE}" == "print-env" ]]; then
  SESSION_DIR="$(get_active_session_dir)"
  if [[ -n "${SESSION_DIR}" && -f "${SESSION_DIR}/gpuapp.env" ]]; then
    cat "${SESSION_DIR}/gpuapp.env"
    exit 0
  fi
  echo "gpuapp.env not found. Start a session first with: gpu.app --start-session" 1>&2
  exit 1
fi

SESSION_ONLY=0
if [[ "${MODE}" == "start-session" ]]; then
  SESSION_ONLY=1
elif [[ $# -eq 0 ]]; then
  echo "Usage: gpu.app [--geometry WIDTHxHEIGHT] --start-session | --print-env | gpu.app <application> [args...]" 1>&2
  exit 1
fi

# it came from modulefile
export QNVSM="/data/apps/extern/app.GUI/2.0"

# Wrapper functions to run TurboVNC tools inside singularity container
Xvnc() {
  singularity exec --nv -B /usr/share/glvnd:/usr/share/glvnd -B /usr/lib/locale/:/usr/lib/locale/,/var:/var,/tmp:/tmp /data/apps/extern/singularity/app.GUI/2.0/rockylinux9.sif /opt/TurboVNC/bin/Xvnc "$@"
}
export -f Xvnc

vncpasswd() {
  singularity exec --nv -B ${HOME}:${HOME} -B /usr/share/glvnd:/usr/share/glvnd -B /usr/lib/locale/:/usr/lib/locale/,/var:/var,/tmp:/tmp /data/apps/extern/singularity/app.GUI/2.0/rockylinux9.sif /opt/TurboVNC/bin/vncpasswd "$@"
}
export -f vncpasswd


cleanup_session_dir() {
  local dir="$1"
  [[ -z "$dir" || ! -d "$dir" ]] && return 0
  if [[ -f "$dir/app.pids" ]]; then
    tac "$dir/app.pids" 2>/dev/null | while read -r pid; do
      [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
    done
    sleep 1
    tac "$dir/app.pids" 2>/dev/null | while read -r pid; do
      [[ -n "$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
    done
  fi
  for pidfile in fluxbox.pid xvnc.pid keepalive.pid vnc_monitor.pid; do
    if [[ -f "$dir/$pidfile" ]]; then
      pid=$(cat "$dir/$pidfile" 2>/dev/null)
      [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  sleep 1
  if [[ -f "$dir/xvnc.pid" ]]; then
    pid=$(cat "$dir/xvnc.pid" 2>/dev/null)
    [[ -n "$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
  fi
}

clean_up () {
  echo "Cleaning up..."
  [[ -n ${VNC_MONITOR_PID} ]] && kill ${VNC_MONITOR_PID} 2>/dev/null || :
  cleanup_session_dir "${SESSION_DIR}"
  [[ -n ${display} ]] && rm -f /tmp/.X${display}-lock /tmp/.X11-unix/X${display} 2>/dev/null || :
  [[ -n "${SESSION_DIR}" ]] && rm -rf "${SESSION_DIR}" 2>/dev/null || true
  [[ -f "${ACTIVE_SESSION_FILE}" ]] && rm -f "${ACTIVE_SESSION_FILE}"
  pkill -P $$ 2>/dev/null || true
  exit ${1:-0}
}

cleanup_previous_active_session() {
  local prev
  prev="$(get_active_session_dir)"
  if [[ -n "$prev" && -d "$prev" ]]; then
    cleanup_session_dir "$prev"
    rm -rf "$prev" 2>/dev/null || true
    rm -f "${ACTIVE_SESSION_FILE}"
  fi
}

create_yml () {
  (
    umask 077
    echo -e "host: $host
port: $port
Password: $password
display: $display
geometry: $GEOMETRY
backend: $BACKEND
websocket: $websocket
spassword: $spassword" > "${SESSION_DIR}/connection.yml"
    cp -f "${SESSION_DIR}/connection.yml" "/home/$USER/connection.yml"
  )
}

create_env_file () {
  (
    umask 077
    cat > "${SESSION_DIR}/gpuapp.env" <<EOF
export DISPLAY=":${display}"
export XAUTHORITY="${HOME}/.Xauthority"
export QT_QPA_PLATFORM="xcb"
export APP_SESSION_DIR="${SESSION_DIR}"
EOF
    cp -f "${SESSION_DIR}/gpuapp.env" "/home/$USER/gpuapp.env"
  )
}

source_helpers () {
  random_number () { shuf -i ${1}-${2} -n 1; }
  export -f random_number
  port_used_python() { python -c "import socket; socket.socket().connect(('$1',$2))" >/dev/null 2>&1; }
  port_used_python3() { python3 -c "import socket; socket.socket().connect(('$1',$2))" >/dev/null 2>&1; }
  port_used_nc(){ nc -w 2 "$1" "$2" < /dev/null > /dev/null 2>&1; }
  port_used_lsof(){ lsof -i :"$2" >/dev/null 2>&1; }
  port_used_bash(){ local bash_supported=$(strings /bin/bash 2>/dev/null | grep tcp); if [ "$bash_supported" == "/dev/tcp/*/*" ]; then (: < /dev/tcp/$1/$2) >/dev/null 2>&1; else return 127; fi; }
  port_used () {
    local port="${1#*:}"
    local host=$((expr "${1}" : '\(.*\):' || echo "localhost") | awk 'END{print $NF}')
    local port_strategies=(port_used_nc port_used_lsof port_used_bash port_used_python port_used_python3)
    for strategy in ${port_strategies[@]}; do
      $strategy $host $port
      status=$?
      if [[ "$status" == "0" ]] || [[ "$status" == "1" ]]; then return $status; fi
    done
    return 127
  }
  export -f port_used
}

source_helpers

choose_geometry () {
  if [[ -n ${GEOMETRY} ]]; then return; fi
  GEOMETRY="1024x768"
  local shell_pgrp terminal_pgrp
  shell_pgrp=$(ps -o pgrp= -p $$ | tr -d ' ')
  terminal_pgrp=$(ps -o tpgid= -p $$ | tr -d ' ')
  if [[ -t 0 && -t 1 && -n ${shell_pgrp} && "${shell_pgrp}" == "${terminal_pgrp}" ]]; then
    while true; do
      echo "Select a resolution for VNC:" 1>&2
      echo "1) 1024x768" 1>&2
      echo "2) 1280x1024" 1>&2
      echo "3) 1920x1080" 1>&2
      echo "4) 2560x1440" 1>&2
      echo "5) Exit" 1>&2
      read -r -p "Enter your choice [1]: " choice
      case "${choice:-1}" in
        1) GEOMETRY="1024x768"; break ;;
        2) GEOMETRY="1280x1024"; break ;;
        3) GEOMETRY="1920x1080"; break ;;
        4) GEOMETRY="2560x1440"; break ;;
        5) echo "Exiting..." 1>&2; exit 0 ;;
        *) echo "Invalid choice. Please try again." 1>&2 ;;
      esac
    done
  fi
}

choose_geometry
cleanup_previous_active_session

mkdir -p "${HOME}/.vnc"
TLS_CERT="${HOME}/.vnc/x509_cert.pem"
TLS_KEY="${HOME}/.vnc/x509_private.pem"
if [[ ! -f "$TLS_CERT" ]] || [[ ! -f "$TLS_KEY" ]] || ! openssl x509 -in "$TLS_CERT" -noout -checkend 86400 >/dev/null 2>&1; then
  echo "Generating TLS certificate..."
  openssl req -new -x509 -days 365 -nodes -out "$TLS_CERT" -keyout "$TLS_KEY" -subj "/C=US/ST=MD/L=Baltimore/O=ARCH/CN=localhost" 2>/dev/null || echo "Certificate generation failed (optional)"
fi

host=$(hostname)
display=1
while [[ -f /tmp/.X${display}-lock ]] || [[ -S /tmp/.X11-unix/X${display} ]] || port_used "localhost:$((5900+display))"; do
  display=$((display+1))
done
export display
port=$((5900+display))
export port
DISPLAY=${host}:${display}
export DISPLAY
SESSION_DIR="${SESSION_ROOT}/display-${display}"
mkdir -p "${SESSION_DIR}"
printf '%s
' "${SESSION_DIR}" > "${ACTIVE_SESSION_FILE}"

xauth_cookie=$(openssl rand -hex 16 2>/dev/null || mcookie 2>/dev/null)
xauth -f "${HOME}/.Xauthority" remove ":${display}" 2>/dev/null
xauth -f "${HOME}/.Xauthority" remove "${host}:${display}" 2>/dev/null
xauth -f "${HOME}/.Xauthority" add ":${display}" MIT-MAGIC-COOKIE-1 "${xauth_cookie}"
xauth -f "${HOME}/.Xauthority" add "${host}:${display}" MIT-MAGIC-COOKIE-1 "${xauth_cookie}"

VNC_LOG="${SESSION_DIR}/vnc.log"
: > "${VNC_LOG}"
ln -sf "${VNC_LOG}" "${HOME}/vnc.log"

change_passwd() {
  echo -ne "$password
$spassword" | singularity exec -B ${HOME}:${HOME} -B /usr/lib/locale/:/usr/lib/locale/,/var:/var,/tmp:/tmp -B /usr/share/glvnd:/usr/share/glvnd /data/apps/extern/singularity/app.GUI/2.0/rockylinux9.sif /opt/TurboVNC/bin/vncpasswd -f > "${SESSION_DIR}/vnc.passwd" 2>/dev/null || true
  cp -f "${SESSION_DIR}/vnc.passwd" "${HOME}/vnc.passwd"
}
create_passwd() { tr -cd a-zA-Z0-9 < /dev/urandom | head -c$1; }

mkdir -p /tmp/.X11-unix
Xvnc :${display} -auth "${HOME}/.Xauthority" -desktop "TurboVNC: ${host}:${display} (${USER})" -geometry "${GEOMETRY}" -depth 24 -rfbauth "${SESSION_DIR}/vnc.passwd" -rfbport ${port} -x509cert "${HOME}/.vnc/x509_cert.pem" -x509key "${HOME}/.vnc/x509_private.pem" -fp catalogue:/etc/X11/fontpath.d -deferupdate 1 -dridir /usr/lib64/dri -registrydir /usr/lib64/xorg -idletimeout 0 >> "${VNC_LOG}" 2>&1 &
VNC_PID=$!
export VNC_PID
echo "$VNC_PID" > "${SESSION_DIR}/xvnc.pid"

sleep 2
kill -0 ${VNC_PID} 2>/dev/null || clean_up 1

echo "Successfully started VNC server on ${host}:${port}..."
password=$(create_passwd 8)
spassword=$(create_passwd 8)
change_passwd
create_yml
create_env_file

cat 1>&2 << END

1. SSH tunnel from your workstation using the following command: (screen sharing for macos)

   ssh -N -L ${port}:${host}:${port} ${USER}@login.rockfish.jhu.edu

2. log in to Remote Desktop VNC Client: 

   localhost:${port}
   Password: $password

END

echo "Shell environment saved to ${SESSION_DIR}/gpuapp.env"
echo "Run: source ${HOME}/gpuapp.env"

export QT_QPA_PLATFORM="xcb"
export XAUTHORITY="${HOME}/.Xauthority"


echo "Waiting for VNC client to connect on port ${port}..."
timeout 120 tail -f "${VNC_LOG}" | while IFS= read -r line; do
  if echo "$line" | grep -q "Full-control authentication enabled"; then
    pkill -f "tail.*${SESSION_DIR}/vnc.log" 2>/dev/null
    break
  fi
done
sleep 3

xrdb -merge "${QNVSM}/fluxbox/Xresources" 2>/dev/null || true
unset DBUS_SESSION_BUS_ADDRESS
eval $(dbus-launch --sh-syntax 2>/dev/null) || true
(
  XAUTH_FILE="${HOME}/.Xauthority"
  fluxbox () {
    SINGULARITYENV_XAUTHORITY=${XAUTH_FILE}     SINGULARITYENV_DISPLAY=":${display}"     singularity exec --nv -B /usr/lib/locale/:/usr/lib/locale/,/var:/var,/tmp:/tmp -B ${XAUTH_FILE}:${XAUTH_FILE} -B /usr/share/glvnd:/usr/share/glvnd -B /tmp/.X11-unix:/tmp/.X11-unix /data/apps/extern/singularity/app.GUI/2.0/rockylinux9.sif fluxbox "$@"
  }
  FLUXBOX_ROOT="${QNVSM:-/data/apps/extern/app.GUI/2.0}/fluxbox"
export FLUXBOX_ROOT
  fluxbox -display ":${display}" -rc "${FLUXBOX_ROOT}/fluxbox.rc"
) &
FLUXBOX_PID=$!
echo "$FLUXBOX_PID" > "${SESSION_DIR}/fluxbox.pid"
sleep 5

export DISPLAY=":${display}"
export XAUTHORITY="${HOME}/.Xauthority"
export QT_QPA_PLATFORM="xcb"


if [[ ${SESSION_ONLY} -eq 1 ]]; then
  echo "Session-only mode active on DISPLAY=:${display}"
  echo 'Run: eval "$(gpu.app --print-env)"'
  echo "Then launch apps from your shell, for example: matlab -desktop &"
  bash -lc 'trap "exit 0" TERM INT; while :; do sleep 3600; done' &
else
  echo "Launching: DISPLAY=:${display} $@"
  "$@" &
fi
APP_PID=$!
disown $APP_PID 2>/dev/null || true
echo "$APP_PID" > "${SESSION_DIR}/keepalive.pid"
echo "App PID: $APP_PID"

(
  client_count=1
  tail -n 0 -f "${VNC_LOG}" 2>/dev/null | while IFS= read -r line; do
    if echo "$line" | grep -q "Full-control authentication enabled"; then
      client_count=$((client_count + 1))
    elif echo "$line" | grep -q "Client .* gone"; then
      client_count=$((client_count - 1))
      if [[ ${client_count} -le 0 ]]; then
        echo "VNC client disconnected; closing session..."
        kill ${FLUXBOX_PID} 2>/dev/null || true
        kill ${APP_PID} 2>/dev/null || true
        break
      fi
    fi
  done
) &
VNC_MONITOR_PID=$!
echo "$VNC_MONITOR_PID" > "${SESSION_DIR}/vnc_monitor.pid"

wait ${FLUXBOX_PID}
clean_up
