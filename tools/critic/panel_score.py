"""Combine a paired critic panel (from round 9) into one result.

Each critic scored two sets, X and Y, one of which is the round under review
and the other the current best (see each packet's key file). The critic's own
calibration offset cancels in its difference (new - best). The panel gain is
the median of the critics' differences; the absolute score of the new round
is the mean of the critics' scores for it.

Usage: python3 -I tools/critic/panel_score.py <key1.json> <critic1.json> [<key2.json> <critic2.json> ...]
  critic*.json holds the JSON block a critic returned.
"""
import json
import statistics
import sys


def mean(v):
    return sum(v) / len(v)


def main(args):
    rows = []
    new_shots = []
    for key_path, critic_path in zip(args[0::2], args[1::2]):
        key = json.load(open(key_path))
        c = json.load(open(critic_path))
        new_label = key['new_label']
        best_label = 'Y' if new_label == 'X' else 'X'
        sc = c['scores']
        new_inner, new_cover = sc[new_label]['inner'], sc[new_label]['cover']
        best_inner, best_cover = sc[best_label]['inner'], sc[best_label]['cover']
        n = mean(new_inner + new_cover)
        b = mean(best_inner + best_cover)
        st = c.get('system', c.get('stone', {}))
        rows.append({'critic': critic_path, 'new': n, 'best': b, 'diff': n - b,
                     'new_inner': mean(new_inner), 'new_cover': mean(new_cover),
                     'stone_new': st.get(new_label), 'stone_best': st.get(best_label)})
        new_shots.append(new_inner + new_cover)
    for r in rows:
        print(f"{r['critic']}: new {r['new']:.2f} (inner {r['new_inner']:.2f}, cover {r['new_cover']:.2f}) "
              f"best {r['best']:.2f} diff {r['diff']:+.2f} system {r['stone_new']} vs {r['stone_best']}")
    gain = statistics.median(r['diff'] for r in rows)
    spread = max(r['diff'] for r in rows) - min(r['diff'] for r in rows)
    absolute = mean([r['new'] for r in rows])
    per_shot = [mean([s[i] for s in new_shots]) for i in range(len(new_shots[0]))]
    print(f"PANEL gain over best {gain:+.2f} (critic spread {spread:.2f}); new absolute {absolute:.2f}; "
          f"inner {mean(per_shot[:8]):.2f} cover {mean(per_shot[8:]):.2f}; min shot {min(per_shot):.2f}")


if __name__ == '__main__':
    main(sys.argv[1:])
