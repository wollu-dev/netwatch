# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/), versioning: [SemVer](https://semver.org/).

## [1.3.0] - 2026-10-04
### Added
- Host names from reverse DNS (`NAME_DNS`, your router) and NetBIOS. Shown in the host list
  and `summary.txt` with a `~` prefix in gray, so they are never mistaken for your labels.
- `NAME_CHANGED` event when a labeled IP reports a different host name.
- `DHCP_POOL` setting. Hosts in the pool are marked with `○` and raise `POOL_HOST` on arrival.
- README section on DHCP reservations and pool layout.
### Changed
- Hosts in `DHCP_POOL` no longer raise `NEW_HOST`.
- The `.1` gateway guess is shown as `~gateway`.
- The port scan skips reverse DNS (`-n`).
### Fixed
- `termux-notification` is wrapped in `timeout` so a stalled Termux:API call cannot hang a scan.

## [1.2.0] - 2026-10-04
### Added
- `MARGIN_X` / `MARGIN_Y` dashboard margins to clear curved screen edges and the top bezel.
- `DEVICE_NAME` setting for the dashboard sys row.

## [1.1.0] - 2026-10-03
### Added
- Live dashboard redesign: boxed status panel, host list with IPs and open ports,
  24-scan trend sparkline, battery temperature, event feed, boot sequence.
- `labels.txt` for naming hosts.
- Scan lock file so the dashboard shows when a scan is running.
### Changed
- All UI text, logs and notifications are in English.
- Event log uses `YYYY-MM-DD HH:MM:SS TAG detail` format.

## [1.0.0] - 2026-10-02
### Added
- Hourly LAN scan with unprivileged nmap, baseline diffing, WAN IP and UPnP tracking,
  Android notifications.
