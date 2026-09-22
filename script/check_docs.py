#!/usr/bin/env python
"""Validate repository-local documentation links and image assets."""
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

root = Path(__file__).resolve().parent.parent
names = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=root, text=True
).splitlines()
errors = []
checked = 0
for name in sorted(set(names)):
    path = root / name
    if path.suffix.lower() != ".md" or not path.is_file():
        continue
    content = re.sub(r"```.*?```", "", path.read_text(), flags=re.S)
    links = re.findall(r"\[[^\]]*\]\(([^\s)]+)(?:\s+[^)]*)?\)", content)
    links += re.findall(r'(?:src|href)="([^"]+)"', content)
    for link in links:
        parts = urlsplit(link)
        if parts.scheme or parts.netloc:
            continue
        target = (path.parent / unquote(parts.path)).resolve() if parts.path else path
        if not target.exists():
            errors.append(f"{name}: missing {link}")
        elif parts.fragment and target.suffix == ".md":
            headings = re.findall(r"^#{1,6}\s+(.+)$", target.read_text(), re.M)
            anchors = [re.sub(r"[^\w\- ]", "", title.lower()).replace(" ", "-") for title in headings]
            if unquote(parts.fragment) not in anchors:
                errors.append(f"{name}: missing anchor {link}")
        checked += 1
for error in errors:
    sys.stderr.write(error + "\n")
sys.stdout.write(f"Checked {checked} local documentation links; {len(errors)} errors.\n")
sys.exit(bool(errors))
