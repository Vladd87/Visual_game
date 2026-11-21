"""Search Openverse (Wikimedia-hosted originals) for reference-photo candidates.

Writes one JSON line per unique candidate (>= 1600 px on the long side) to the
output file. Respects anonymous rate limits: one request every few seconds,
honours Retry-After on 429.

Usage: [OV_SOURCE=wikimedia|inaturalist] python3 -I openverse_search.py <out.jsonl> <query> [<query> ...]
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

UA = "LanternRefFetcher/0.1 (game art reference research)"
API = "https://api.openverse.org/v1/images/"


def get(url):
    for attempt in range(6):
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                wait = int(e.headers.get("Retry-After") or 30)
                print(f"  429, waiting {wait}s", file=sys.stderr)
                time.sleep(wait + 1)
                continue
            raise
    raise RuntimeError("rate limited too many times")


def main():
    out, queries = sys.argv[1], sys.argv[2:]
    seen = set()
    try:
        with open(out) as f:
            for line in f:
                seen.add(json.loads(line)["id"])
    except FileNotFoundError:
        pass
    with open(out, "a") as f:
        for q in queries:
            for page in (1, 2):
                params = {"q": q, "page_size": 20, "page": page, "source": os.environ.get("OV_SOURCE", "wikimedia")}
                d = get(API + "?" + urllib.parse.urlencode(params))
                kept = 0
                for r in d.get("results", []):
                    w, h = r.get("width") or 0, r.get("height") or 0
                    if max(w, h) < 1600 or r["id"] in seen:
                        continue
                    if (r.get("filetype") or "jpg").lower() not in ("jpg", "jpeg", "png"):
                        continue
                    seen.add(r["id"])
                    kept += 1
                    rec = {k: r.get(k) for k in (
                        "id", "title", "url", "thumbnail", "width", "height", "creator",
                        "creator_url", "license", "license_version", "license_url",
                        "foreign_landing_url", "source", "tags")}
                    rec["tags"] = [t.get("name") for t in (rec["tags"] or [])][:12]
                    rec["url"] = (rec["url"] or "").split("?")[0]  # drop utm_* params
                    rec["query"] = q
                    f.write(json.dumps(rec) + "\n")
                print(f"{q!r} p{page}: {len(d.get('results', []))} results, kept {kept}", file=sys.stderr)
                time.sleep(4)
                if d.get("page_count", 1) <= page:
                    break


if __name__ == "__main__":
    main()
