# UptimeTray (macOS 13+ Menu Bar App)

Native macOS menubar app (Swift + SwiftUI `MenuBarExtra`) that mirrors the uptime calculations in [`../uptime.py`](../uptime.py) using the BigChange RSS history feed:

- Feed: `https://status.bigchange.com/history.rss`
- Rolling window (default 30 days)
- Merged downtime intervals
- Overall uptime %
- Incident count + average incident resolution time
- Per-component uptime % + downtime

## Open in Xcode

Open `UptimeTray/UptimeTray.xcodeproj` and run the `UptimeTray` scheme.

## Settings

Use the menu’s **Settings…** item to change:

- Window length in days
- Optional target uptime % (values below show in red)


