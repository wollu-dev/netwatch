#!/data/data/com.termux/files/usr/bin/bash
# ┌──────────────────────────────────────────────────────┐
# │ netwatch :: home network watchdog for Termux         │
# │   netwatch.sh          run one scan (cron, hourly)   │
# │   netwatch.sh show     live dashboard                │
# └──────────────────────────────────────────────────────┘
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
export LC_ALL=C.UTF-8   # char-width math for box drawing

# ---------- config ----------
SUBNET="192.168.35.0/24"
PORTS="21,22,23,53,80,135,139,443,445,554,1883,3389,5000,5357,5900,8000,8080,8443,9100,62078"
BASE="$HOME/netwatch"
KEEP_DAYS=7
DEVICE_NAME="s9"   # shown in the dashboard sys row
MARGIN_X=2   # dashboard side margin (curved edges)
MARGIN_Y=1   # dashboard top margin
# ----------------------------

VERSION="1.2"
SELF="$(readlink -f "$0")"
LOG="$BASE/alerts.log"
LOCK="$BASE/.scanning"
mkdir -p "$BASE/runs"

# ======================================================
#  dashboard
# ======================================================
E=$'\e'; R="$E[0m"; BLD="$E[1m"; GRY="$E[90m"
GRN="$E[32m"; CYN="$E[36m"; YEL="$E[33m"; RED="$E[31m"
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

declare -A PMAP LABEL NEWSET
DATA_KEY=""; LOG_MTIME=""

rep() { local s="" i; for ((i=0; i<$2; i++)); do s+="$1"; done; printf '%s' "$s"; }

fit() { # truncate text to width with ellipsis
  local t="$1" w="$2"
  (( w < 2 )) && w=2
  (( ${#t} > w )) && t="${t:0:$((w-1))}…"
  printf '%s' "$t"
}

row() { # boxed key/value row: row <key> <value> [color]
  local inner=$((BW-4)) v pad
  v=$(fit "$2" $((inner-7)))
  pad=$((inner-7-${#v}))
  out+="${PADX}${GRY}│${R} ${CYN}$(printf '%-6s' "$1")${R} ${3}${v}${R}$(rep ' ' $pad) ${GRY}│${R}${E}[K"$'\n'
}

spark() { # host-count trend over the last 24 scans
  local ch=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █) cs=() mx=1 c d s=""
  for d in $(ls -1d "$BASE"/runs/*/ 2>/dev/null | tail -n 24); do
    c=0; [ -f "$d/hosts.txt" ] && c=$(grep -c . "$d/hosts.txt")
    cs+=("$c"); (( c > mx )) && mx=$c
  done
  for c in "${cs[@]}"; do s+="${ch[$(( c * 7 / mx ))]}"; done
  printf '%s' "$s"
}

read_batt() {
  local j pct tmp st
  j=$(timeout 3 termux-battery-status 2>/dev/null)
  pct=$(grep -o '"percentage": *[0-9]*' <<< "$j" | grep -o '[0-9]*$')
  tmp=$(grep -o '"temperature": *[0-9.]*' <<< "$j" | grep -o '[0-9.]*$')
  st=$(grep -o '"status": *"[A-Z_]*"' <<< "$j" | cut -d'"' -f4)
  if [ -z "$pct" ]; then BATT="n/a (termux-api?)"; BCOL="$GRY"; return; fi
  BATT=$(printf '%s%% · %.1f°C · %s' "$pct" "${tmp:-0}" "${st,,}")
  BCOL=""
  awk -v t="${tmp:-0}" 'BEGIN{exit !(t>=40)}' && BCOL="$RED"   # hot battery = red
}

load_data() {
  [ -f "$BASE/last_run" ] || return
  local key ip port name _
  key="$(stat -c %Y "$BASE/last_run" "$BASE/labels.txt" 2>/dev/null | tr '\n' ' ')"
  if [ "$key" != "$DATA_KEY" ]; then
    DATA_KEY=$key
    RUN=$(cat "$BASE/last_run")
    HOSTS=$(sort -t. -k4,4n "$RUN/hosts.txt" 2>/dev/null)
    NHOST=$(grep -c . <<< "$HOSTS")
    PMAP=(); NEWSET=(); LABEL=()
    [ -f "$RUN/ports.txt" ] && while read -r ip port _; do
      [ -n "$ip" ] && PMAP[$ip]+="${port%/*} "
    done < "$RUN/ports.txt"
    [ -f "$RUN/new_hosts.txt" ] && while read -r ip; do
      [ -n "$ip" ] && NEWSET[$ip]=1
    done < "$RUN/new_hosts.txt"
    [ -f "$BASE/labels.txt" ] && while read -r ip name; do
      [[ -z "$ip" || "$ip" == \#* ]] || LABEL[$ip]="$name"
    done < "$BASE/labels.txt"
    SCAN_START=""; SCAN_END=""
    [ -f "$RUN/meta" ] && read -r SCAN_START SCAN_END < "$RUN/meta"
    PUB=$(cat "$BASE/public_ip" 2>/dev/null)
    SPARK=$(spark)
  fi
  local lm; lm=$(stat -c %Y "$LOG" 2>/dev/null)
  if [ "$lm" != "$LOG_MTIME" ]; then LOG_MTIME=$lm; EVENTS=$(tail -n 5 "$LOG" 2>/dev/null); fi
}

render() {
  local now clock live left right up
  now=$(date +%s); clock=$(date +%H:%M:%S)
  live="●"; (( tick % 2 )) && live="○"
  left="╭─[ NETWATCH ]"; right="[ $live $clock ]─╮"

  out="${E}[H"
  local i; for ((i=0; i<MARGIN_Y; i++)); do out+="${E}[K"$'\n'; done
  out+="${PADX}${GRY}╭─[ ${R}${BLD}${GRN}NETWATCH${R}${GRY} ]$(rep '─' $((BW-${#left}-${#right})))[ ${R}${GRN}${live}${R} ${clock}${GRY} ]─╮${R}${E}[K"$'\n'

  up=$(awk '{s=int($1); printf "%dd %02dh %02dm", s/86400, s%86400/3600, s%3600/60}' /proc/uptime 2>/dev/null)
  row "sys"  "${DEVICE_NAME} · termux · up ${up:-n/a}"
  row "wan"  "${PUB:-unknown}"
  row "lan"  "$SUBNET"
  if [ -f "$LOCK" ]; then
    row "scan" "running ${SPIN[$((tick % 10))]}" "$YEL"
  elif [ -n "$SCAN_END" ]; then
    local age=$(( (now - SCAN_END) / 60 )) took=$(( SCAN_END - SCAN_START ))
    local next=$(( 60 - 10#$(date +%M) )) col=""
    (( age > 70 )) && col="$RED"   # cron stalled?
    row "scan" "$(date -d @"$SCAN_END" +%H:%M) · ${age}m ago · ${took}s · next ${next}m" "$col"
  else
    row "scan" "no data yet" "$YEL"
  fi
  row "trend" "${SPARK:-—}"
  row "batt"  "$BATT" "$BCOL"
  out+="${PADX}${GRY}╰$(rep '─' $((BW-2)))╯${R}${E}[K"$'\n'

  # ---- hosts ----
  out+="${PADX}${E}[K"$'\n'
  out+="${PADX}${GRN}▌${R} ${BLD}HOSTS${R} ${GRY}// ${NHOST:-0} online${R}${E}[K"$'\n'
  local ip lbl p bullet fixed room
  while read -r ip; do
    [ -z "$ip" ] && continue
    lbl="${LABEL[$ip]:-}"
    [ -z "$lbl" ] && [[ "$ip" == *.1 ]] && lbl="gateway"
    p="${PMAP[$ip]:-}"; p="${p% }"; [ -z "$p" ] && p="-"
    if [ -n "${NEWSET[$ip]:-}" ]; then bullet="${YEL}+${R}"; else bullet="${GRN}●${R}"; fi
    fixed=$(printf '%-15s %-10s ' "$ip" "$(fit "${lbl:--}" 10)")
    room=$((BW - 4 - ${#fixed}))
    out+="${PADX}  ${bullet} ${fixed}${GRY}$(fit "$p" $room)${R}${E}[K"$'\n'
  done <<< "$HOSTS"

  # ---- events ----
  out+="${PADX}${E}[K"$'\n'
  out+="${PADX}${GRN}▌${R} ${BLD}EVENTS${R} ${GRY}// last 5${R}${E}[K"$'\n'
  if [ -z "$EVENTS" ]; then
    out+="${PADX}  ${GRY}// all quiet. no anomalies detected.${R}${E}[K"$'\n'
  else
    local d t tg rest
    while read -r d t tg rest; do
      [ -z "$tg" ] && continue
      out+="${PADX}  ${GRY}${d:5} ${t:0:5}${R} ${RED}${tg}${R} $(fit "$rest" $((BW - 15 - ${#tg})))${E}[K"$'\n'
    done <<< "$EVENTS"
  fi

  # ---- footer ----
  out+="${PADX}${E}[K"$'\n'
  out+="${PADX}${GRN}❯${R} ${GRY}netwatch v${VERSION} · [r]escan · [q]uit${R}  ${CYN}${SPIN[$((tick % 10))]}${R}${E}[K"
  out+="${E}[J"
  printf '%s' "$out"
}

boot_seq() {
  printf '%s' "${E}[2J${E}[H"
  local i; for ((i=0; i<MARGIN_Y; i++)); do echo; done
  printf '%s\n\n' "${PADX}${GRY}netwatch v${VERSION} :: booting${R}"
  local s
  for s in "init tty" "mount ~/netwatch" "load host table" "load port map" \
           "attach event log" "probe battery" "arm watchdog"; do
    printf '%s\n' "${PADX}${GRY}[  ${GRN}OK${GRY}  ]${R} $s"
    sleep 0.12
  done
  sleep 0.4
  printf '%s' "${E}[2J"
}

cleanup() { printf '%s' "${E}[?25h${R}${E}[2J${E}[H"; exit 0; }

dashboard() {
  PADX=$(rep ' ' "$MARGIN_X")
  trap cleanup INT TERM
  printf '%s' "${E}[?25l"
  boot_seq
  tick=0
  while true; do
    W=$(stty size 2>/dev/null | cut -d' ' -f2); W=${W:-48}
    BW=$(( W - 2*MARGIN_X )); (( BW > 64 )) && BW=64; (( BW < 36 )) && BW=36
    (( tick % 30 == 0 )) && read_batt
    load_data
    render
    tick=$((tick + 1))
    if read -rsn1 -t 1 key; then
      case "$key" in
        q) cleanup ;;
        r) [ -f "$LOCK" ] || (nohup "$SELF" >/dev/null 2>&1 &) ;;
      esac
    fi
  done
}

[ "$1" = "show" ] && { dashboard; exit 0; }

# ======================================================
#  scan
# ======================================================
# skip if another scan is running (locks older than 30m are treated as stale)
[ -n "$(find "$LOCK" -mmin -30 2>/dev/null)" ] && exit 0
touch "$LOCK"; trap 'rm -f "$LOCK"' EXIT

START=$(date +%s)
RUN="$BASE/runs/$(date +%Y%m%d-%H%M)"
mkdir -p "$RUN"
alerts=()
alert() { alerts+=("$*"); }

# ---- 1) discovery + port scan ----
nmap -sn --unprivileged -T4 -oG "$RUN/ping.gnmap" "$SUBNET" >/dev/null 2>&1
nmap -sT -Pn -T4 --max-retries 1 --host-timeout 60s --open \
     -p "$PORTS" -oG "$RUN/scan.gnmap" "$SUBNET" >/dev/null 2>&1

# normalize to "IP port/proto service"
grep "Ports:" "$RUN/scan.gnmap" | while IFS= read -r line; do
  ip=$(echo "$line" | awk '{print $2}')
  echo "$line" | sed 's/.*Ports: //; s/\tIgnored.*//' | tr ',' '\n' \
    | grep '/open/' \
    | awk -F/ -v ip="$ip" '{gsub(/ /,"",$1); print ip, $1"/"$3, ($5==""?"?":$5)}'
done | sort -u > "$RUN/ports.txt"

# a host is "online" if it answered discovery or has any open port
{ awk '/Status: Up/{print $2}' "$RUN/ping.gnmap"; awk '{print $1}' "$RUN/ports.txt"; } \
  | sort -u > "$RUN/hosts.txt"

[ -s "$RUN/hosts.txt" ] || alert SCAN_EMPTY "no hosts (check wifi / SUBNET)"

# ---- 2) MAC addresses (may be blocked on Android 10+) ----
if ip neigh 2>/dev/null | grep -q lladdr; then
  ip neigh | awk '/lladdr/ && !/FAILED/ {print $1, tolower($5)}' | sort -u > "$RUN/macs.txt"
  if [ -s "$BASE/known_macs.txt" ]; then
    while read -r ip mac; do
      alert UNKNOWN_MAC "$mac ($ip)"
    done < <(awk 'NR==FNR{k[tolower($1)];next} !($2 in k)' "$BASE/known_macs.txt" "$RUN/macs.txt")
  fi
fi

# ---- 3) diff against cumulative baseline ----
first_run=false
[ -s "$BASE/seen_hosts.txt" ] || first_run=true
touch "$BASE/seen_hosts.txt" "$BASE/seen_ports.txt" "$BASE/seen_upnp.txt" "$RUN/new_hosts.txt"

if ! $first_run; then
  comm -13 "$BASE/seen_hosts.txt" "$RUN/hosts.txt" > "$RUN/new_hosts.txt"
  while read -r h; do [ -n "$h" ] && alert NEW_HOST "$h"; done < "$RUN/new_hosts.txt"
  while read -r p; do [ -n "$p" ] && alert NEW_PORT "$p"; done \
    < <(comm -13 "$BASE/seen_ports.txt" "$RUN/ports.txt")
fi

# ---- 4) WAN: public IP + UPnP port forwards ----
PUB=$(curl -s --max-time 10 https://ifconfig.me)
PREV_PUB=$(cat "$BASE/public_ip" 2>/dev/null)
if [ -n "$PUB" ]; then
  [ -n "$PREV_PUB" ] && [ "$PUB" != "$PREV_PUB" ] && alert WAN_CHANGED "$PREV_PUB -> $PUB"
  echo "$PUB" > "$BASE/public_ip"
fi

if command -v upnpc >/dev/null; then
  upnpc -l 2>/dev/null | awk '$2=="TCP"||$2=="UDP"{print $2, $3, $4}' | sort -u > "$RUN/upnp.txt"
  if ! $first_run; then
    while read -r u; do [ -n "$u" ] && alert NEW_UPNP "$u"; done \
      < <(comm -13 "$BASE/seen_upnp.txt" "$RUN/upnp.txt")
  fi
fi

# ---- 5) update baseline ----
sort -u "$BASE/seen_hosts.txt" "$RUN/hosts.txt" -o "$BASE/seen_hosts.txt"
sort -u "$BASE/seen_ports.txt" "$RUN/ports.txt" -o "$BASE/seen_ports.txt"
[ -f "$RUN/upnp.txt" ] && sort -u "$BASE/seen_upnp.txt" "$RUN/upnp.txt" -o "$BASE/seen_upnp.txt"

# ---- 6) log + android notification ----
if [ ${#alerts[@]} -gt 0 ]; then
  for a in "${alerts[@]}"; do echo "$(date '+%F %T') $a" >> "$LOG"; done
  command -v termux-notification >/dev/null && \
    termux-notification --id netwatch --title "netwatch // ${#alerts[@]} event(s)" \
      --content "$(printf '%s\n' "${alerts[@]}")"
fi

# ---- 7) plain-text summary (for cat / ssh) ----
{
  echo "netwatch // $(date '+%F %H:%M')"
  echo "wan   : ${PUB:-unknown}"
  echo "hosts : $(grep -c . "$RUN/hosts.txt")"
  $first_run && echo "note  : first run, baseline saved"
  echo
  while read -r h; do
    [ -z "$h" ] && continue
    printf '  %-16s %s\n' "$h" "$(awk -v ip="$h" '$1==ip{printf "%s ", $2}' "$RUN/ports.txt")"
  done < <(sort -t. -k4,4n "$RUN/hosts.txt")
  if [ -s "$RUN/upnp.txt" ]; then echo; echo "upnp:"; sed 's/^/  /' "$RUN/upnp.txt"; fi
  echo
  echo "recent events:"
  tail -n 5 "$LOG" 2>/dev/null | sed 's/^/  /'
} > "$BASE/summary.txt"

# ---- 8) finalize ----
echo "$START $(date +%s)" > "$RUN/meta"
echo "$RUN" > "$BASE/last_run"
find "$BASE/runs" -mindepth 1 -maxdepth 1 -type d -mtime +"$KEEP_DAYS" -exec rm -rf {} +
