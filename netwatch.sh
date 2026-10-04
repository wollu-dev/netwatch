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
NAME_DNS=""               # router IP, if it serves DHCP host names over DNS ("" = off)
DHCP_POOL="100-199"       # last-octet range the router hands out dynamically ("" = off)
SILENT_PROBE=1            # find hosts that drop all probes via kernel ARP (0 = off)
KEEP_DAYS=7
DEVICE_NAME="s9"   # shown in the dashboard sys row
MARGIN_X=2   # dashboard side margin (curved edges)
MARGIN_Y=1   # dashboard top margin
# ----------------------------

VERSION="1.4"
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

declare -A PMAP LABEL NEWSET NAME
DATA_KEY=""; LOG_MTIME=""

rep() { local s="" i; for ((i=0; i<$2; i++)); do s+="$1"; done; printf '%s' "$s"; }

fit() { # truncate text to width with ellipsis
  local t="$1" w="$2"
  (( w < 2 )) && w=2
  (( ${#t} > w )) && t="${t:0:$((w-1))}…"
  printf '%s' "$t"
}

padr() { # right-pad to width by characters (printf '%-Ns' counts bytes)
  local t="$1" n=$(( $2 - ${#1} ))
  (( n > 0 )) && t+=$(rep ' ' "$n")
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

load_labels() { # labels.txt -> LABEL[ip]
  local ip name
  LABEL=()
  [ -f "$BASE/labels.txt" ] || return
  while read -r ip name; do
    [[ -z "$ip" || "$ip" == \#* ]] || LABEL[$ip]="$name"
  done < "$BASE/labels.txt"
}

# Reserved devices live outside the pool, so a pool address means "not registered".
subnet_hosts() { # subnet_hosts <a.b.c.d/n>: usable addresses, one per line
  local a b c d n="${1#*/}" base i x
  IFS=. read -r a b c d <<< "${1%/*}"
  base=$(( ((a << 24) | (b << 16) | (c << 8) | d) & ((0xFFFFFFFF << (32 - n)) & 0xFFFFFFFF) ))
  for ((i = 1; i < (1 << (32 - n)) - 1; i++)); do
    x=$((base + i))
    echo "$((x >> 24 & 255)).$((x >> 16 & 255)).$((x >> 8 & 255)).$((x & 255))"
  done
}

in_pool() { # in_pool <ip>
  [ -n "$DHCP_POOL" ] || return 1
  local o="${1##*.}"
  (( o >= ${DHCP_POOL%-*} && o <= ${DHCP_POOL#*-} ))
}

# Once labels.txt lists your devices, it is the allowlist for addresses outside the
# pool: "never seen before" is too weak, since one visit makes an IP known forever.
unlisted() { # unlisted <ip>; needs LABEL loaded
  (( ${#LABEL[@]} > 0 )) && ! in_pool "$1" && [ -z "${LABEL[$1]:-}" ]
}

# What to call a host. Your labels win; device-reported names and guesses
# get a "~" so they never look like something you confirmed.
display_name() { # display_name <ip> <discovered name>
  if [ -n "${LABEL[$1]:-}" ]; then printf '%s' "${LABEL[$1]}"
  elif [ -n "$2" ]; then printf '~%s' "$2"
  elif [[ "$1" == *.1 ]]; then printf '~gateway'
  fi
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
    PMAP=(); NEWSET=(); NAME=()
    [ -f "$RUN/ports.txt" ] && while read -r ip port _; do
      [ -n "$ip" ] && PMAP[$ip]+="${port%/*} "
    done < "$RUN/ports.txt"
    [ -f "$RUN/new_hosts.txt" ] && while read -r ip; do
      [ -n "$ip" ] && NEWSET[$ip]=1
    done < "$RUN/new_hosts.txt"
    [ -f "$RUN/names.txt" ] && while read -r ip name _; do
      [ -n "$ip" ] && NAME[$ip]="$name"
    done < "$RUN/names.txt"
    load_labels
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
  local ip lbl lcol p bullet ipcol lblcol room
  while read -r ip; do
    [ -z "$ip" ] && continue
    lbl=$(display_name "$ip" "${NAME[$ip]:-}"); lbl="${lbl:--}"
    lcol=""; [[ "$lbl" == "~"* || "$lbl" == "-" ]] && lcol="$GRY"
    p="${PMAP[$ip]:-}"; p="${p% }"; [ -z "$p" ] && p="-"
    if unlisted "$ip"; then bullet="${RED}!${R}"
    elif [ -n "${NEWSET[$ip]:-}" ]; then bullet="${YEL}+${R}"
    elif in_pool "$ip"; then bullet="${GRY}○${R}"
    else bullet="${GRN}●${R}"; fi
    ipcol=$(printf '%-15s ' "$ip")
    lblcol="$(padr "$(fit "$lbl" 10)" 10) "
    room=$((BW - 4 - ${#ipcol} - ${#lblcol}))
    out+="${PADX}  ${bullet} ${ipcol}${lcol}${lblcol}${R}${GRY}$(fit "$p" $room)${R}${E}[K"$'\n'
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
# Termux resolv.conf points at public DNS, which cannot name LAN hosts; ask the router.
dns=(-n); [ -n "$NAME_DNS" ] && dns=(--dns-servers "$NAME_DNS")
nmap -sn --unprivileged -T4 "${dns[@]}" -oG "$RUN/ping.gnmap" "$SUBNET" >/dev/null 2>&1
nmap -sT -Pn -n -T4 --max-retries 1 --host-timeout 60s --open \
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

# ---- 1a) silent hosts (firewalled PCs, sleeping phones) ----
# A host that drops every probe looks the same to nmap as an empty address. But the kernel
# must ARP a LAN address before a TCP connect: an empty one fails in ~3s with "No route to
# host", a present one answers ARP and then times out or refuses. No root, no ARP table.
if [ "$SILENT_PROBE" = 1 ] && [ "${SUBNET#*/}" -ge 22 ] 2>/dev/null; then   # /22+: ~1000 probes max
  n=0
  while read -r ip; do
    grep -qxF "$ip" "$RUN/hosts.txt" && continue
    { err=$(timeout 5 bash -c "echo > /dev/tcp/$ip/9" 2>&1); rc=$?
      [[ $rc -eq 0 || $rc -eq 124 || "$err" == *refused* ]] && echo "$ip"; } &
    (( ++n % 64 == 0 )) && wait   # bounded batches: the phone, not the LAN, is the limit
  done < <(subnet_hosts "$SUBNET") > "$RUN/silent.txt"
  wait
  sort -u "$RUN/hosts.txt" "$RUN/silent.txt" -o "$RUN/hosts.txt"
fi

[ -s "$RUN/hosts.txt" ] || alert SCAN_EMPTY "no hosts (check wifi / SUBNET)"

# ---- 1b) host names (device-reported: shown, never trusted) ----
declare -A HNAME=() HSRC=()
add_name() { # add_name <ip> <raw name> <source>; first source wins
  local n="${2%%.*}"
  n="${n,,}"; n="${n// /-}"; n="${n//[^a-z0-9-]/}"; n="${n:0:15}"
  [ -n "$1" ] && [ -n "$n" ] && [ -z "${HNAME[$1]:-}" ] && { HNAME[$1]="$n"; HSRC[$1]="$3"; }
}

# reverse DNS: "Host: 192.168.35.23 (galaxy-s9.lan)	Status: Up"
while read -r ip n; do add_name "$ip" "$n" rdns; done < <(
  awk '/Status: Up/ { n=$3; gsub(/[()]/, "", n); if (n != "") print $2, n }' "$RUN/ping.gnmap")

# mDNS (Apple, Chromecast, printers): ask each host directly on 5353. A unicast query
# gets a unicast answer, so this works without root or a multicast lock. Needs dnsutils.
if command -v dig >/dev/null; then
  while read -r ip; do
    [ -z "$ip" ] || [ -n "${HNAME[$ip]:-}" ] && continue
    { n=$(timeout 4 dig -x "$ip" @"$ip" -p 5353 +short +time=2 +tries=1 2>/dev/null \
            | grep -v '^;' | head -n 1)
      [ -n "$n" ] && echo "$ip $n"; } &
  done < "$RUN/hosts.txt" > "$RUN/mdns.txt"
  wait
  while read -r ip n; do add_name "$ip" "$n" mdns; done < "$RUN/mdns.txt"
fi

# NetBIOS for the rest (Windows / Samba). Optional: a failure just leaves names empty.
grep -vxF -f <(printf '%s\n' "${!HNAME[@]}") "$RUN/hosts.txt" > "$RUN/nameless.txt"
if [ -s "$RUN/nameless.txt" ]; then
  timeout 120 nmap -sn -Pn -n --unprivileged --script nbstat \
    -iL "$RUN/nameless.txt" -oN "$RUN/nbstat.txt" >/dev/null 2>&1
  [ -f "$RUN/nbstat.txt" ] && while read -r ip n; do add_name "$ip" "$n" netbios; done < <(
    awk '/^Nmap scan report for/ { ip=$NF; gsub(/[()]/, "", ip) }
         /NetBIOS name:/ { s=$0; sub(/.*NetBIOS name: /, "", s); sub(/,.*/, "", s); print ip, s }' \
      "$RUN/nbstat.txt")
fi

for ip in "${!HNAME[@]}"; do echo "$ip ${HNAME[$ip]} ${HSRC[$ip]}"; done \
  | sort -t. -k4,4n > "$RUN/names.txt"

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

load_labels
prev=$(cat "$BASE/last_run" 2>/dev/null)
arrived() { ! grep -qxF "$1" "$prev/hosts.txt" 2>/dev/null; }  # not online last scan

if ! $first_run; then
  # pool addresses are reused by whoever connects, so "never seen" means nothing there
  comm -13 "$BASE/seen_hosts.txt" "$RUN/hosts.txt" \
    | while read -r h; do in_pool "$h" || echo "$h"; done > "$RUN/new_hosts.txt"
  # with an allowlist, UNLISTED_HOST below covers these
  (( ${#LABEL[@]} > 0 )) || while read -r h; do
    [ -n "$h" ] && alert NEW_HOST "$h"
  done < "$RUN/new_hosts.txt"
  # instead, report each arrival in the pool
  while read -r h; do
    in_pool "$h" && arrived "$h" && alert POOL_HOST "$h (${HNAME[$h]:--})"
  done < "$RUN/hosts.txt"
  while read -r p; do [ -n "$p" ] && alert NEW_PORT "$p"; done \
    < <(comm -13 "$BASE/seen_ports.txt" "$RUN/ports.txt")
fi

# Not baseline-based, so it runs on the first scan too. Alerts on each arrival, not
# every hour; the dashboard keeps showing the host while it stays.
while read -r h; do
  [ -n "$h" ] && unlisted "$h" && arrived "$h" && alert UNLISTED_HOST "$h (${HNAME[$h]:--})"
done < "$RUN/hosts.txt"

# A labeled (reserved) IP reporting a different name may now be another device.
declare -A LASTNAME=()
[ -f "$BASE/last_names.txt" ] && while read -r ip n; do
  [ -n "$ip" ] && LASTNAME[$ip]="$n"
done < "$BASE/last_names.txt"
for ip in "${!HNAME[@]}"; do
  old="${LASTNAME[$ip]:-}"
  [ -n "${LABEL[$ip]:-}" ] && [ -n "$old" ] && [ "$old" != "${HNAME[$ip]}" ] && \
    alert NAME_CHANGED "$ip $old -> ${HNAME[$ip]}"
  LASTNAME[$ip]="${HNAME[$ip]}"
done
for ip in "${!LASTNAME[@]}"; do echo "$ip ${LASTNAME[$ip]}"; done \
  | sort -t. -k4,4n > "$BASE/last_names.txt"

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
    timeout 10 termux-notification --id netwatch --title "netwatch // ${#alerts[@]} event(s)" \
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
    n=$(display_name "$h" "${HNAME[$h]:-}")
    printf '  %-16s %-16s %s\n' "$h" "${n:--}" "$(awk -v ip="$h" '$1==ip{printf "%s ", $2}' "$RUN/ports.txt")"
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
