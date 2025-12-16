#!/usr/bin/env python3
import argparse
import re
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

FEED_URL = "https://status.bigchange.com/history.rss"
WINDOW_DAYS = 30

# ANSI color codes for terminal output
RED = "\033[31m"
RESET = "\033[0m"


def fetch_feed(url: str = FEED_URL) -> bytes:
    with urllib.request.urlopen(url, timeout=15) as resp:
        return resp.read()


def parse_duration(description: str) -> timedelta | None:
    """
    Parse a 'Duration:' line from the description, e.g.:
      'Duration: 30 minutes'
      'Duration: 1 hour and 51 minutes'
      'Duration: 20 hours'
    Returns a timedelta, or None if no duration is found.
    """
    if not description:
        return None

    # Extract the rest of the line after 'Duration:'
    m = re.search(r"Duration:\s*([^\n\r]+)", description, flags=re.IGNORECASE)
    if not m:
        return None

    dur_text = m.group(1)
    hours = 0
    minutes = 0

    m_hours = re.search(r"(\d+)\s*hour", dur_text, flags=re.IGNORECASE)
    if m_hours:
        hours = int(m_hours.group(1))

    m_mins = re.search(r"(\d+)\s*minute", dur_text, flags=re.IGNORECASE)
    if m_mins:
        minutes = int(m_mins.group(1))

    if hours == 0 and minutes == 0:
        return None

    return timedelta(hours=hours, minutes=minutes)


def iter_items(feed_xml: bytes):
    root = ET.fromstring(feed_xml)
    channel = root.find("channel")
    if channel is None:
        return

    for item in channel.findall("item"):
        pub_el = item.find("pubDate")
        if pub_el is None or not (pub_el.text or "").strip():
            continue

        try:
            pub_date = parsedate_to_datetime(pub_el.text)
        except Exception:
            continue

        if pub_date.tzinfo is None:
            pub_date = pub_date.replace(tzinfo=timezone.utc)

        desc_el = item.find("description")
        desc_text = desc_el.text if desc_el is not None and desc_el.text else ""

        # Try to extract the type (Incident / Maintenance / etc.) from the description
        incident_type = ""
        m_type = re.search(r"Type:\s*([A-Za-z]+)", desc_text, flags=re.IGNORECASE)
        if m_type:
            incident_type = m_type.group(1).strip().lower()

        # Try to extract affected components from the description
        components = []
        m_comp = re.search(
            r"Affected Components:\s*([^\n\r]+)", desc_text, flags=re.IGNORECASE
        )
        if m_comp:
            comp_text = m_comp.group(1)
            for part in comp_text.split(","):
                name = part.strip()
                if name:
                    components.append(name)

        title_el = item.find("title")
        title_text = title_el.text.strip() if title_el is not None and title_el.text else ""

        yield {
            "title": title_text,
            "pub_date": pub_date,
            "description": desc_text,
            "type": incident_type,
            "components": components,
        }


def merge_intervals(intervals):
    """
    Given a list of (start, end) datetimes, merge overlapping ones.
    Returns a new list of merged (start, end).
    """
    if not intervals:
        return []

    intervals = sorted(intervals, key=lambda x: x[0])
    merged = [intervals[0]]

    for start, end in intervals[1:]:
        last_start, last_end = merged[-1]
        if start <= last_end:  # overlap
            merged[-1] = (last_start, max(last_end, end))
        else:
            merged.append((start, end))

    return merged


def compute_uptime(days: int = WINDOW_DAYS):
    now = datetime.now(timezone.utc)
    window_start = now - timedelta(days=days)

    feed_xml = fetch_feed()
    intervals = []
    incident_total = timedelta()
    incident_count = 0
    component_intervals = {}  # component -> list[(start, end)]

    for item in iter_items(feed_xml):
        dur = parse_duration(item["description"])
        if dur is None:
            # No explicit duration, skip for uptime calculations
            continue

        start = item["pub_date"]
        end = start + dur

        # Track incident resolution times (using full duration) where the
        # incident started inside the window and has a known duration.
        if item.get("type") == "incident" and window_start <= start <= now:
            incident_total += dur
            incident_count += 1

        # Clip to analysis window
        if end <= window_start or start >= now:
            continue

        clipped_start = max(start, window_start)
        clipped_end = min(end, now)
        if clipped_start < clipped_end:
            intervals.append((clipped_start, clipped_end))

            # Track downtime per component for this clipped interval
            for comp in item.get("components", []):
                component_intervals.setdefault(comp, []).append(
                    (clipped_start, clipped_end)
                )

    merged = merge_intervals(intervals)
    total_downtime = sum((end - start for start, end in merged), timedelta())

    window = now - window_start
    if window.total_seconds() <= 0:
        uptime_pct = 100.0
    else:
        downtime_secs = total_downtime.total_seconds()
        uptime_pct = max(0.0, 1.0 - downtime_secs / window.total_seconds()) * 100.0

    avg_incident_resolution = (
        incident_total / incident_count if incident_count > 0 else None
    )

    # Compute uptime per component
    component_stats = {}
    for comp, comp_intervals in component_intervals.items():
        merged_comp = merge_intervals(comp_intervals)
        comp_downtime = sum(
            (end - start for start, end in merged_comp),
            timedelta(),
        )
        if window.total_seconds() <= 0:
            comp_uptime = 100.0
        else:
            comp_uptime = max(
                0.0,
                1.0 - comp_downtime.total_seconds() / window.total_seconds(),
            ) * 100.0

        component_stats[comp] = {
            "uptime_pct": comp_uptime,
            "downtime": comp_downtime,
            "intervals": merged_comp,
        }

    return (
        uptime_pct,
        total_downtime,
        merged,
        incident_count,
        avg_incident_resolution,
        component_stats,
    )


def main():
    parser = argparse.ArgumentParser(
        description="Compute overall percentage uptime for the BigChange product "
                    "over a specified window (default 30 days) "
                    "using the BigChange status RSS feed."
    )
    parser.add_argument(
        "-d",
        "--days",
        type=int,
        default=WINDOW_DAYS,
        help=f"Number of days to look back from now (default: {WINDOW_DAYS})",
    )
    parser.add_argument(
        "-t",
        "--target-uptime",
        type=float,
        default=None,
        help=(
            "Required uptime percentage. If overall or component uptime "
            "falls below this value, that line will be shown in red."
        ),
    )
    args = parser.parse_args()

    (
        uptime_pct,
        total_downtime,
        intervals,
        incident_count,
        avg_incident_resolution,
        component_stats,
    ) = compute_uptime(args.days)

    print(f"Window length: {args.days} days")
    print(
        "Total recorded downtime: "
        f"{total_downtime} ({total_downtime.total_seconds() / 60:.2f} minutes)"
    )
    if args.target_uptime is not None:
        print(f"Required uptime target: {args.target_uptime:.5f}%")

    overall_line = f"Overall uptime: {uptime_pct:.5f}%"
    if args.target_uptime is not None and uptime_pct < args.target_uptime:
        overall_line = f"{RED}{overall_line}{RESET}"
    print(overall_line)

    print(f"Number of downtime intervals used: {len(intervals)}")
    if avg_incident_resolution is not None:
        print(
            "Average incident resolution time: "
            f"{avg_incident_resolution} "
            f"({avg_incident_resolution.total_seconds() / 60:.2f} minutes) "
            f"across {incident_count} incident(s)"
        )
    else:
        print(
            "Average incident resolution time: "
            "no incident entries with a duration found in the window"
        )

    if component_stats:
        print("\nAverage uptime per component over window:")
        for comp in sorted(component_stats.keys()):
            stats = component_stats[comp]
            dt = stats["downtime"]
            line = (
                f"  {comp}: uptime {stats['uptime_pct']:.5f}% "
                f"(downtime {dt} / {dt.total_seconds() / 60:.2f} minutes)"
            )
            if (
                args.target_uptime is not None
                and stats["uptime_pct"] < args.target_uptime
            ):
                line = f"{RED}{line}{RESET}"
            print(line)
    else:
        print(
            "\nAverage uptime per component: "
            "no component-level downtime entries with a duration found in the window"
        )

    # Uncomment to see individual intervals
    # for start, end in intervals:
    #     print(start.isoformat(), "->", end.isoformat(),
    #           f"({(end - start).total_seconds() / 60:.1f} minutes)")


if __name__ == "__main__":
    main()