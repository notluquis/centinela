#!/usr/bin/env python3
"""Prepend a release to appcast.xml, the feed Sparkle reads.

Sparkle ships `generate_appcast`, which wants a directory holding every past archive so it can
compute binary deltas. This project publishes one zip per release and does not do deltas, so the
whole apparatus buys a download of every previous release on every run. Writing the item is a
dozen lines instead.

    Tools/appcast.py --version 0.3.0 --zip build/Centinela.zip \
        --signature "$(sign_update build/Centinela.zip)" --notes-url https://...

The EdDSA signature is NOT computed here on purpose: it needs the private key, which lives in the
release runner's environment and nowhere else.
"""

import argparse
import datetime
import pathlib
import re
import xml.etree.ElementTree as ET

VACIO = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Centinela</title>
    <link>https://github.com/notluquis/centinela</link>
    <description>Your Sentry issues in the macOS menu bar.</description>
    <language>en</language>
  </channel>
</rss>
"""


def parse_signature(texto: str) -> tuple[str, str]:
    """`sign_update` prints `sparkle:edSignature="..." length="..."`. Both halves are needed."""
    firma = re.search(r'sparkle:edSignature="([^"]+)"', texto)
    largo = re.search(r'length="(\d+)"', texto)
    if not firma or not largo:
        raise SystemExit(f"could not read sign_update output: {texto!r}")
    return firma.group(1), largo.group(1)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--appcast", default="appcast.xml")
    ap.add_argument("--version", required=True, help="short version, e.g. 0.3.0")
    ap.add_argument("--build", required=True, help="CFBundleVersion")
    ap.add_argument("--url", required=True, help="download URL of the zip")
    ap.add_argument("--signature", required=True, help="raw sign_update output")
    ap.add_argument("--notes-url", required=True, help="where 'Learn more' should point")
    ap.add_argument(
        "--notes-file",
        help="markdown to embed in the item. Sparkle renders it inline, which beats pointing at "
             "a GitHub release page: that page comes with its own chrome and the update dialog "
             "ends up showing 'Compare', 'github-actions released this' and a commit list around "
             "the actual notes.",
    )
    ap.add_argument("--minimum-system-version", default="14.0")
    args = ap.parse_args()

    firma, largo = parse_signature(args.signature)
    ruta = pathlib.Path(args.appcast)
    if not ruta.exists() or not ruta.read_text().strip():
        ruta.write_text(VACIO)

    ET.register_namespace("sparkle", "http://www.andymatuschak.org/xml-namespaces/sparkle")
    arbol = ET.parse(ruta)
    canal = arbol.getroot().find("channel")
    if canal is None:
        raise SystemExit("appcast.xml has no <channel>")

    SP = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"

    # Republishing the same version would offer people an update to what they already run.
    for viejo in canal.findall("item"):
        if (viejo.findtext(f"{SP}shortVersionString") or "") == args.version:
            canal.remove(viejo)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {args.version}"
    ET.SubElement(item, f"{SP}version").text = args.build
    ET.SubElement(item, f"{SP}shortVersionString").text = args.version
    ET.SubElement(item, f"{SP}minimumSystemVersion").text = args.minimum_system_version
    if args.notes_file:
        # `sparkle:format="markdown"` is one of the three formats Sparkle accepts, alongside
        # `plain-text` and `html` (`SUAppcastItem.m`). With it the CHANGELOG section goes in
        # verbatim, with no conversion step to get wrong.
        #
        # Note: Sparkle ignores the description when the appcast fails signature validation. It is
        # not signed here, which reads as "unchecked" rather than "failed", so it renders.
        descripcion = ET.SubElement(item, "description")
        descripcion.set(f"{SP}format", "markdown")
        descripcion.text = pathlib.Path(args.notes_file).read_text().strip()
        # The link out stays, as "Learn more" rather than as the notes themselves.
        ET.SubElement(item, f"{SP}fullReleaseNotesLink").text = args.notes_url
    else:
        ET.SubElement(item, f"{SP}releaseNotesLink").text = args.notes_url
    ET.SubElement(item, "pubDate").text = datetime.datetime.now(
        datetime.timezone.utc
    ).strftime("%a, %d %b %Y %H:%M:%S +0000")
    ET.SubElement(item, "enclosure", {
        "url": args.url,
        f"{SP}edSignature": firma,
        "length": largo,
        "type": "application/octet-stream",
    })

    # Newest first: Sparkle picks the highest version, but a human reading the file should not
    # have to scroll to the bottom to see what shipped last.
    canal.insert(len(list(canal.findall("*"))) - len(canal.findall("item")), item)

    ET.indent(arbol, space="  ")
    arbol.write(ruta, encoding="utf-8", xml_declaration=True)
    print(f"appcast.xml updated: {args.version} (build {args.build}), signature {firma[:12]}…")


if __name__ == "__main__":
    main()
