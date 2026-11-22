"""Fill tools/critic/critic_prompt_paired.md for one panel critic.

Usage: python3 -I tools/critic/render_prompt.py <packet_dir> <with_ab: 0|1> <out.md>
"""
import os
import sys

AB_BULLET = ('- `ab/pairK_A.jpg` and `ab/pairK_B.jpg`: blind pairs. In each pair exactly one image is a real '
             'photograph and one is a render. They have been cropped and re-encoded identically, with all '
             'metadata stripped. The real photos in the pairs are not among `references/`.')
AB_SECTION = '''
## 4. Blind A/B
For each pair, say which image (A or B) is the real photograph, your confidence (50–100 %), and the single detail that decided it.
'''
AB_JSON = ',\n "ab": [{"pair": 1, "real": "A", "confidence": 90}, ...]'


def main(packet, with_ab, out):
    here = os.path.dirname(os.path.abspath(__file__))
    t = open(os.path.join(here, 'critic_prompt_paired.md')).read()
    ab = with_ab == '1'
    t = t.replace('{PACKET}', packet)
    t = t.replace('{AB_BULLET}', AB_BULLET if ab else '')
    t = t.replace('{AB_SECTION}', AB_SECTION if ab else '\n')
    t = t.replace('{JSON_N}', '5' if ab else '4')
    t = t.replace('{AB_JSON}', AB_JSON if ab else '')
    open(out, 'w').write(t)


if __name__ == '__main__':
    main(*sys.argv[1:4])
