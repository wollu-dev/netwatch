# netwatch

> Turn a spare Android phone into a desk display that keeps an eye on your home network. No root required.

netwatch is a single Bash script for [Termux](https://termux.dev). Every hour it scans
your LAN with nmap, remembers the devices and open ports it has seen, and notifies you
when something new shows up. Between scans it is a live terminal dashboard for your desk.

It is a desk gadget first: a pleasant way to see what is on your network and to notice the
obvious. It is **not** a security monitor and will not catch someone who is trying to hide.
See [What netwatch is not](#what-netwatch-is-not).

```
  ╭─[ NETWATCH ]──────────────[ ● 14:32:07 ]─╮
  │ sys    s9 · termux · up 3d 04h 12m       │
  │ wan    203.0.113.7                       │
  │ lan    192.168.35.0/24                   │
  │ scan   14:00 · 32m ago · 200s · next 28m │
  │ trend  ▃▃▄▅▅▆▇█▇▆▅▅▄▃▃▃▄▅▅▆▇▇▆▅          │
  │ batt   82% · 31.2°C · charging           │
  ╰──────────────────────────────────────────╯

  ▌ HOSTS // 5 online
    ● 192.168.35.1    gateway    53 80 443
    ● 192.168.35.12   desktop    135 445 3389
    ● 192.168.35.23   s9         8022
    ! 192.168.35.57   -          -
    ○ 192.168.35.140  ~galaxy-s9 62078

  ▌ EVENTS // last 5
    10-03 13:02 UNLISTED_HOST 192.168.35.57 (-)
    10-03 14:03 POOL_HOST 192.168.35.140 (galaxy-s9)

  ❯ netwatch v1.4 · [r]escan · [q]uit  ⠋
```

## Features

- **Host discovery and port scan** of your LAN every hour, using unprivileged nmap, plus a
  no-root check that also finds firewalled PCs and idle phones.
- **Baseline diffing.** Alerts only on hosts, ports and UPnP forwards never seen before,
  so a device with a fixed IP dropping off Wi-Fi and coming back does not spam you.
  (Devices in the DHCP pool raise `POOL_HOST` on every arrival.)
- **WAN watch.** Tracks your public IP and UPnP port forwards on the router.
- **Works with DHCP.** Reserve addresses for your own devices and netwatch treats the
  router's dynamic pool as "not registered" (see [Router setup](#router-setup)).
- **Host names** from mDNS, NetBIOS and (if your router serves them) reverse DNS,
  shown apart from your own labels.
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
pkg install termux-api miniupnpc dnsutils   # optional (dnsutils: mDNS host names)

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
| `NAME_DNS`    | empty (off)           | Router IP, if it answers reverse DNS with DHCP host names |
| `DHCP_POOL`   | `100-199`             | Last-octet range of the router's dynamic pool; empty = off |
| `KEEP_DAYS`   | `7`                   | How long per-scan records are kept            |
| `DEVICE_NAME` | `s9`                  | Name shown in the dashboard                   |
| `SILENT_PROBE`| `1`                   | Also find hosts that drop all probes (adds ~20 s per scan); `0` = off |
| `MARGIN_X`    | `2`                   | Dashboard side margin; raise for curved edges |
| `MARGIN_Y`    | `1`                   | Dashboard top margin                          |

Optional files in `~/netwatch` (samples in [`examples/`](examples)):

- `labels.txt` – `IP name` per line, shown in the host list. Keep names ASCII, ≤ 10 chars.
  Label only reserved addresses: a label on a dynamic address will follow the address,
  not the device. **It is also the allowlist:** once it has any entry, every host outside
  `DHCP_POOL` that is not listed raises `UNLISTED_HOST` each time it comes online, even if
  it was seen before. List all your fixed devices, the router included.
- `known_macs.txt` – MAC allowlist. Any other MAC raises `UNKNOWN_MAC`.

In the host list, a plain name is your label. A name starting with `~` was reported by the
device itself (or, for `~gateway`, guessed). Devices can report any name, so treat `~` names
as hints, not identity. A gray `○` marks a host in the DHCP pool, a red `!` a host outside
the pool that is not in `labels.txt`.

## Router setup

netwatch identifies devices by IP. With DHCP, IPs can change, so pin your own devices:

1. In the router's DHCP settings, shrink the dynamic pool, e.g. `.100`–`.199`.
2. Give each of your devices a fixed address outside the pool, e.g. `.2`–`.99`, in one of two ways:
   - **DHCP reservation** (static lease) on the router, keyed by MAC. Some routers allow only
     a few, or only inside the pool.
   - **Manual IP** on the device itself (network settings → IP → static/manual). Use the router's
     address as the gateway and keep the DNS servers the device already receives. On phones and
     laptops this is saved per Wi-Fi network, so other networks are not affected.
3. Check the device's private (random) MAC setting. *Off* and *Fixed* (one stable address per
   network) are both fine; avoid *Rotating* or
   *Change daily*. A reservation needs the MAC to stay the same. A manual IP does not, but a
   stable MAC keeps the device recognizable in the router's client list.
4. Set `DHCP_POOL` to match, and list the fixed addresses in `labels.txt`.

Anything that then appears in the pool is a device you have not registered: a guest,
a new gadget, or something that should not be there.

The split is a convention that well-behaved devices follow, not a security boundary.
Anyone on your network can set their own IP outside the pool, or reuse one of yours.

### Without fixed IPs

Some ISP routers allow only a couple of reservations and give no internet access to
addresses outside their DHCP range, so the setup above is not possible. netwatch still
works without it: most routers hand the same IP back to the same MAC, so addresses at
home change rarely.

1. Leave every device on DHCP, with a stable MAC (*Off* or *Fixed*, not *Rotating*).
   Use the few reservations you have for always-on devices such as a NAS.
2. Set `DHCP_POOL=""`.
3. Fill `labels.txt` with the addresses the devices have now (the router's client list
   shows them).

When an address changes, the device shows up as `UNLISTED_HOST` under its new IP: check
the router's client list and update `labels.txt`. The same alert also covers guests and
unknown devices, so look before you dismiss it.

## Events

Logged to `~/netwatch/alerts.log` as `YYYY-MM-DD HH:MM:SS TAG detail`.

| Tag           | Raised when                                   |
|---------------|-----------------------------------------------|
| `UNLISTED_HOST` | A host outside the DHCP pool and not in `labels.txt` comes online (not online in the previous scan) |
| `NEW_HOST`    | An IP outside the DHCP pool appears for the first time (only while `labels.txt` is empty) |
| `POOL_HOST`   | A host comes online in the DHCP pool (not online in the previous scan) |
| `NAME_CHANGED`| A labeled IP reports a different host name than before |
| `NEW_PORT`    | A host exposes a port never seen before       |
| `NEW_UPNP`    | A new UPnP port forward appears on the router |
| `WAN_CHANGED` | Your public IP changes                        |
| `UNKNOWN_MAC` | A MAC not in `known_macs.txt` is on the LAN   |
| `SCAN_EMPTY`  | A scan finds nothing (Wi-Fi down, wrong subnet) |

To reset the baseline, delete `~/netwatch/seen_*.txt` and run a scan.

## What netwatch is not

netwatch looks at your network from the outside, one hour at a time, by IP address.
Without root it cannot see link-layer (MAC) data on modern Android, and it cannot
tell two devices apart if they use the same IP. That makes it good at noticing the
honest and the careless, and blind to anyone deliberately avoiding it.

| Someone on your network who... | netwatch |
|---|---|
| picks an IP outside the pool that is not in `labels.txt` | raises `UNLISTED_HOST` on every arrival |
| does the same without a `labels.txt` | raises `NEW_HOST` once; stays quiet on later visits |
| opens a port not seen before | raises `NEW_PORT` |
| takes the IP of one of your devices while it is off | stays quiet |
| does that and answers no name queries | stays quiet (a name disappearing is ignored) |
| ignores pings and drops every probe | is found by the silent-host check (it must still answer ARP) |
| connects and leaves between two scans | is never seen |
| reports a host name | name shown as a hint; names can be anything |

What actually keeps people out lives on the router:

1. WPA2/WPA3 with a long passphrase, and **WPS turned off**.
2. A separate guest network, so visitors cannot reach your devices.
3. A changed router admin password (not the one on the sticker), and current firmware.
4. The router's list of connected **wireless clients**. It shows every associated MAC,
   including devices that set their own IP and never asked DHCP. Checking it now and then
   is a better audit than anything netwatch can do from a phone.

Use netwatch to enjoy watching your network, and to spot the new smart plug, the guest
who never left, or the port you forgot to close. Do not rely on it to detect an intruder.

## Limitations

- **No root, so no ARP scan.** Hosts that drop every probe (Windows on a *Public* network,
  idle phones) are still found by the silent-host check (`SILENT_PROBE`): before any TCP
  connect the kernel has to ARP the address, so an empty address fails fast with
  "No route to host" while a present one times out or refuses. A phone in deep sleep can
  answer ARP too late and be missed for a scan. Your router's client list remains the most
  complete source.
- **MAC addresses** come from the kernel ARP table, which Android 10+ often hides from apps.
  When it is hidden, MAC features switch off and netwatch tracks by IP.
- **Host names** come from the devices themselves. mDNS covers Apple devices, Chromecast
  and most printers; NetBIOS covers Windows (only on a *Private* network profile) and Samba.
  Many ISP routers run no LAN DNS, so reverse DNS is off by default: test with
  `dig -x <router IP> @<router IP>` before setting `NAME_DNS`. Many Android phones and
  IoT devices report no name at all.
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
