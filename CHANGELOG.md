# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/), versioning: [SemVer](https://semver.org/).

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
