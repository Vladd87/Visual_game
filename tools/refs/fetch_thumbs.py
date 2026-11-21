"""Download small screening thumbnails (Wikimedia thumbnailer or Openverse thumb proxy).

Index list "all" selects every candidate.

Usage: python3 -I fetch_thumbs.py <cands.jsonl> <outdir> <idx,idx,...>
"""
import json
import os
import sys
import time
import urllib.request

UA = "LanternRefFetcher/0.1 (game art reference research)"


def main():
    cands = [json.loads(l) for l in open(sys.argv[1])]
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    if sys.argv[3] == "all":
        idxs = list(range(len(cands)))
    else:
        idxs = [int(x) for x in sys.argv[3].split(",") if x.strip()]
    for i in idxs:
        r = cands[i]
        path = os.path.join(out, f"{i:03d}.jpg")
        if os.path.exists(path):
            continue
        if "/wikipedia/commons/" in r["url"]:
            # Wikimedia's own thumbnailer at a standard width step (Openverse's
            # thumb proxy answers 424 for Wikimedia-hosted items).
            tail = r["url"].split("?")[0].split("/wikipedia/commons/")[1]
            name = tail.split("/")[-1]
            url = f"https://upload.wikimedia.org/wikipedia/commons/thumb/{tail}/500px-{name}"
            if name.lower().endswith((".tif", ".tiff")):
                url += ".jpg"
        else:
            url = f"https://api.openverse.org/v1/images/{r['id']}/thumb/"
        for attempt in range(5):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": UA})
                with urllib.request.urlopen(req, timeout=60) as resp:
                    data = resp.read()
                with open(path, "wb") as f:
                    f.write(data)
                break
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    # Honour the server's Retry-After in full before retrying.
                    wait = int(e.headers.get("Retry-After") or 60)
                    print(f"{i}: 429, honouring Retry-After {wait}s", file=sys.stderr, flush=True)
                    time.sleep(wait + 1)
                    continue
                print(f"{i}: HTTP {e.code}", file=sys.stderr, flush=True)
                break
            except Exception as e:  # noqa: BLE001
                print(f"{i}: {e}", file=sys.stderr)
                time.sleep(3)
        # Polite pacing between requests (Wikimedia is throttling this IP).
        time.sleep(6.0 if "/wikipedia/commons/" in r["url"] else 0.8)


if __name__ == "__main__":
    main()
