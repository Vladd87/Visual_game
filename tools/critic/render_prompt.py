"""Fill a critic prompt template.

Usage: python3 -I tools/critic/render_prompt.py <packet_dir> <with_ab: 0|1> <out.md> [system]
       python3 -I tools/critic/render_prompt.py --ab <ab_packet_dir> <out.md>
  system: stone (default), light, rain, vegetation, lantern, post, grade,
          view, water, wet, mist (M11)

From round 10 the scoring critics run with with_ab = 0 and the A/B pairs go
to their own critic (critic_prompt_ab.md), which sees nothing else.
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


SYSTEMS = {
    'stone': ('the rocks, banks and ground (shape, material, moss, wetness, how they sit in the water and the ground)', 'the rocks and ground'),
    'light': ('the lighting and atmosphere (time of day, light balance and colour, exposure, blacks and highlights, mist and haze)', 'the lighting'),
    'rain': ('the rain (drops, streaks, splashes, ripples, wetness)', 'the rain'),
    'vegetation': ('the plants (ferns, grass, moss cushions, leaves)', 'the plants'),
    'lantern': ('the lantern and the fireflies (paper, glow, reflections, light on the scene)', 'the lantern and fireflies'),
    'post': ('the camera and lens (depth of field, motion, grain, bloom, sharpness)', 'the camera rendering'),
    'grade': ('the colour grade and tonal range', 'the grade'),
    # M11
    'view': ('the camera viewpoint and lens, and the paper lantern itself (perspective, framing, sense of scale, the paper)', 'the viewpoint and the lantern'),
    'water': ('the water (its surface, reflections, glints and glitter, ripples and rain on it)', 'the water'),
    'wet': ('how wet the scene looks (sheen and glints on ground, stone, leaves and plants in the rain)', 'the wetness'),
    'mist': ('the air around the light (glow, mist and haze in the wet air)', 'the air and glow'),
}


def main(packet, with_ab, out, system='stone'):
    here = os.path.dirname(os.path.abspath(__file__))
    t = open(os.path.join(here, 'critic_prompt_paired.md')).read()
    ab = with_ab == '1'
    t = t.replace('{PACKET}', packet)
    t = t.replace('{AB_BULLET}', AB_BULLET if ab else '')
    t = t.replace('{AB_SECTION}', AB_SECTION if ab else '\n')
    t = t.replace('{JSON_N}', '5' if ab else '4')
    t = t.replace('{AB_JSON}', AB_JSON if ab else '')
    desc, short = SYSTEMS[system]
    t = t.replace('{SYSTEM_DESC}', desc).replace('{SYSTEM_SHORT}', short)
    # From M11 the two builds may frame the scene differently: describe the
    # camera neutrally.
    t = t.replace('from a fixed high, tilted camera', 'from a camera tilted down at it')
    open(out, 'w').write(t)


if __name__ == '__main__':
    if sys.argv[1] == '--ab':
        here = os.path.dirname(os.path.abspath(__file__))
        t = open(os.path.join(here, 'critic_prompt_ab.md')).read().replace('{PACKET}', sys.argv[2])
        open(sys.argv[3], 'w').write(t)
    else:
        main(*sys.argv[1:5])
