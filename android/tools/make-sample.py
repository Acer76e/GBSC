#!/usr/bin/env python3
"""Turn the live web app (index.html at the repo root) into the sample build
that gets bundled into the APK.

The APK is a student-facing sample meant to be handed to someone else, so the
copy differs from the real app in three ways:

  1. No parent dashboard. The ⚙️ button is the only way in, so removing it
     leaves the student side and nothing else.
  2. The greeting says "Hi Student!" instead of "Hi Julia!" until whoever is
     holding the phone sets a name.
  3. No service worker. It exists to cache the site for offline use; inside the
     APK every file is already on the device.

Everything else — all ten subjects, all the games, all the trophies — is the
app exactly as it ships to the web.

Run from anywhere:  python3 android/tools/make-sample.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "index.html"
DST = ROOT / "android" / "app" / "src" / "main" / "assets" / "index.html"


def replace(html, pattern, repl, expected, what):
    """Apply a substitution and fail loudly if the app has drifted."""
    html, n = re.subn(pattern, repl, html)
    if n != expected:
        sys.exit(f"make-sample: expected {expected} match(es) for {what}, found {n}. "
                 "index.html changed — update android/tools/make-sample.py.")
    return html


def main():
    html = SRC.read_text(encoding="utf-8")

    html = replace(
        html,
        r'\s*<button class="settings-icon"[^>]*>⚙️</button>',
        "",
        2,
        "the parent-dashboard button",
    )

    html = replace(
        html,
        r'lsGet\("g6_name","Julia"\)',
        'lsGet("g6_name","Student")',
        1,
        "the default student name",
    )

    html = replace(
        html,
        r'name: newer\.name \|\| "Julia"',
        'name: newer.name || "Student"',
        1,
        "the default name used when merging synced data",
    )

    html = replace(
        html,
        r'if \("serviceWorker" in navigator\) \{\n.*?\n\}\n',
        "",
        1,
        "the service-worker registration",
    )

    DST.parent.mkdir(parents=True, exist_ok=True)
    DST.write_text(html, encoding="utf-8")
    print(f"make-sample: wrote {DST.relative_to(ROOT)} ({len(html):,} bytes)")


if __name__ == "__main__":
    main()
