You are an exacting photo editor. Everything you may look at is in this folder: `{PACKET}`. Use only files in it. Do not open, search or list anything outside it. Do not create or modify files anywhere.

`ab/pairK_A.jpg` and `ab/pairK_B.jpg` (K = 1..4) are blind pairs. In each pair exactly one image is a real photograph and the other is a computer render. Both were cropped to the same shape and size and re-encoded identically, with all metadata stripped. The subjects are water, wet stone, moss, warm light in fog or rain, and dusk.

Look at every image (use the Read tool on each .jpg). For each pair, say which image (A or B) is the real photograph, your confidence (50–100 %), and the single visual detail that decided it.

End with one fenced JSON block:
```json
{"ab": [{"pair": 1, "real": "A", "confidence": 90}, ...]}
```
