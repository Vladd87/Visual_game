"""Search Wikimedia Commons (File namespace) for reference-photo candidates.

Appends candidates (>= 1600 px on the long side) to a JSONL file using the same
record shape as openverse_search.py. Requests are spaced out and Retry-After
is honoured in full.

Usage: python3 -I commons_search.py <out.jsonl> <query> [<query> ...]
"""
import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request

UA = "LanternRefFetcher/0.1 (game art reference research)"
API = "https://commons.wikimedia.org/w/api.php"


def get(params):
    url = API + "?" + urllib.parse.urlencode(params)
    while True:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                wait = int(e.headers.get("Retry-After") or 60)
                print(f"  429, honouring Retry-After {wait}s", file=sys.stderr, flush=True)
                time.sleep(wait + 1)
                continue
            raise


def strip_tags(s):
    return html.unescape(re.sub(r"<[^>]+>", "", s or "")).strip()


def main():
    out, queries = sys.argv[1], sys.argv[2:]
    seen = set()
    try:
        with open(out) as f:
            for line in f:
                seen.add(json.loads(line)["url"])
    except FileNotFoundError:
        pass
    with open(out, "a") as f:
        for q in queries:
            d = get({
                "action": "query", "format": "json", "generator": "search",
                "gsrsearch": f"{q} filetype:bitmap", "gsrnamespace": 6, "gsrlimit": 30,
                "prop": "imageinfo", "iiprop": "url|size|extmetadata",
                "iiextmetadatafilter": "Artist|LicenseShortName|LicenseUrl|ImageDescription",
                "maxlag": 5,
            })
            kept = 0
            for page in (d.get("query", {}).get("pages", {}) or {}).values():
                ii = (page.get("imageinfo") or [{}])[0]
                w, h = ii.get("width", 0), ii.get("height", 0)
                url = ii.get("url", "").split("?")[0]  # drop utm_* tracking params
                if max(w, h) < 1600 or url in seen or not url.lower().endswith((".jpg", ".jpeg", ".png")):
                    continue
                seen.add(url)
                meta = ii.get("extmetadata", {})
                rec = {
                    "id": f"commons:{page.get('pageid')}",
                    "title": page.get("title", "").removeprefix("File:"),
                    "url": url,
                    "width": w, "height": h,
                    "creator": strip_tags(meta.get("Artist", {}).get("value")),
                    "license": meta.get("LicenseShortName", {}).get("value"),
                    "license_url": meta.get("LicenseUrl", {}).get("value"),
                    "foreign_landing_url": ii.get("descriptionurl"),
                    "source": "wikimedia-commons-api",
                    "description": strip_tags(meta.get("ImageDescription", {}).get("value"))[:200],
                    "query": q,
                }
                f.write(json.dumps(rec) + "\n")
                kept += 1
            print(f"{q!r}: kept {kept}", file=sys.stderr, flush=True)
            time.sleep(30)


if __name__ == "__main__":
    main()
