# netwatch

> Turn a spare Android phone into an always-on home network watchdog. No root required.

netwatch is a single Bash script for [Termux](https://termux.dev). Every hour it scans
your LAN with nmap, remembers every device and open port it has ever seen, and pings
your phone the moment something new shows up. Between scans it doubles as a live
terminal dashboard for your desk.

```
  ╭─[ NETWATCH ]──────────────[ ● 14:32:07 ]─╮
  │ sys    s9 · termux · up 3d 04h 12m       │
  │ wan    203.0.113.7                       │
  │ lan    192.168.35.0/24                   │
  │ scan   14:00 · 32m ago · 200s · next 28m │
  │ trend  ▃▃▄▅▅▆▇█▇▆▅▅▄▃▃         │
  │ batt   82% · 31.2°C · charging           │
  ╰──────────────────────────────────────────╯

  ▌ HOSTS // 5 online
    ● 192.168.35.1    gateway    53 80 443
    ● 192.168.35.12   desktop    135 445 3389
    ● 192.168.35.23   s9         8022
    ● 192.168.35.57   -          -
    + 192.168.35.140  -          -

  ▌ EVENTS // last 5
    10-03 14:03 NEW_HOST 192.168.35.140

  ❯ netwatch v1.2 · [r]escan · [q]uit  ⠋
```

## Features

- **Host discovery and port scan** of your LAN every hour, using unprivileged nmap.
- **Baseline diffing.** Alerts only on hosts, ports and UPnP forwards never seen before,
  so a phone dropping off Wi-Fi and coming back does not spam you.
- **WAN watch.** Tracks your public IP and UPnP port forwards on the router.
- **MAC allowlist** when the ARP table is readable (see [Limitations](#limitations)).
- **Android notifications** via Termux:API.
- **Live dashboard** with host list, open ports, 24-scan trend line, battery temperature
  and an event feed. Flicker-free, adapts to screen width, keeps clear of curved edges.
- **One file, no build.** Copy it to a phone and run it.

## Requirements

- Android phone with [Termux](https://f-droid.org/packages/com.termux/) from F-Droid
- Optional: [Termux:API](https://f-droid.org/packages/com.termux.api/) (notifications, battery),
  [Termux:Boot](https://f-droid.org/packages/com.termux.boot/) (start on boot),
  [Termux:Styling](https://f-droid.org/packages/com.termux.styling/) (fonts, colors)

Install all Termux apps from the **same source**. Mixing F-Droid and Play Store builds breaks plugins.

## Install

```bash
pkg update && pkg upgrade
pkg install git nmap curl cronie termux-services
pkg install termux-api miniupnpc        # optional

git clone https://github.com/<you>/netwatch ~/projects/netwatch
ln -s ~/projects/netwatch/netwatch.sh $PREFIX/bin/netwatch
```

Clone outside `~/netwatch`: that directory is where netwatch stores its data.

Set your subnet at the top of `netwatch.sh`, then run the first scan. The first run
saves a baseline and raises no alerts, so have your devices online when you run it.

```bash
netwatch            # first scan, takes a few minutes
netwatch show       # dashboard
```

### Run every hour

Restart Termux once after installing `termux-services`, then:

```bash
sv-enable crond
crontab -e
```

```cron
0 * * * * /data/data/com.termux/files/usr/bin/netwatch
```

### Keep it alive

Android aggressively kills background apps. On the phone:

- Settings → Apps → Termux → Battery → **Optimize battery usage** → switch to *All* → turn Termux **off**
- Settings → Device care → Battery → App power management → make sure Termux is not in *Sleeping apps*
- In Termux: long-press → More → **Keep screen on** (keeps full brightness while the dashboard is up)

To start after a reboot, copy [`examples/start.sh`](examples/start.sh) to `~/.termux/boot/`,
`chmod +x` it, and open the Termux:Boot app once.

## Configuration

Edit the block at the top of `netwatch.sh`.

| Variable      | Default               | Meaning                                       |
|---------------|-----------------------|-----------------------------------------------|
| `SUBNET`      | `192.168.35.0/24`     | LAN range to scan                             |
| `PORTS`       | common service ports  | TCP ports checked on every host               |
| `BASE`        | `~/netwatch`          | Data directory                                |
| `KEEP_DAYS`   | `7`                   | How long per-scan records are kept            |
| `DEVICE_NAME` | `s9`                  | Name shown in the dashboard                   |
| `MARGIN_X`    | `2`                   | Dashboard side margin; raise for curved edges |
| `MARGIN_Y`    | `1`                   | Dashboard top margin                          |

Optional files in `~/netwatch` (samples in [`examples/`](examples)):

- `labels.txt` – `IP name` per line, shown in the host list. Keep names ASCII, ≤ 10 chars.
- `known_macs.txt` – MAC allowlist. Any other MAC raises `UNKNOWN_MAC`.

## Events

Logged to `~/netwatch/alerts.log` as `YYYY-MM-DD HH:MM:SS TAG detail`.

| Tag           | Raised when                                   |
|---------------|-----------------------------------------------|
| `NEW_HOST`    | An IP appears that has never been seen        |
| `NEW_PORT`    | A host exposes a port never seen before       |
| `NEW_UPNP`    | A new UPnP port forward appears on the router |
| `WAN_CHANGED` | Your public IP changes                        |
| `UNKNOWN_MAC` | A MAC not in `known_macs.txt` is on the LAN   |
| `SCAN_EMPTY`  | A scan finds nothing (Wi-Fi down, wrong subnet) |

To reset the baseline, delete `~/netwatch/seen_*.txt` and run a scan.

## Limitations

- **No root, so no ARP scan.** Hosts that block every probed port and ignore TCP pings
  can be missed. Your router's DHCP client list remains the most complete source.
- **MAC addresses** come from the kernel ARP table, which Android 10+ often hides from apps.
  When it is hidden, MAC features switch off and netwatch tracks by IP.
- **External ports.** Scanning your own public IP from inside the LAN goes through the
  router's NAT loopback and does not show what the internet sees. netwatch watches UPnP
  forwards instead. For a real outside view, scan from mobile data.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `bad interpreter: ...bash^M` | File has Windows line endings: `sed -i 's/\r$//' netwatch.sh` |
| `sv-enable: unable to change to service directory` | Restart Termux so `SVDIR` is set |
| Dashboard says no data | Run `netwatch` once and wait for it to finish |
| Right edge of the box is hidden | Increase `MARGIN_X` |
| `batt n/a` | Install the Termux:API app and `pkg install termux-api` |

## Responsible use

Only scan networks you own or are explicitly allowed to test.

## License

See [LICENSE](LICENSE).
