# Device screenshots, history

Screenshots from the target phone (Galaxy Z Fold8 Ultra, Adreno 840) of builds
whose look has since changed. Kept as a record; not given to the critics.
Current ones go in `captures/device/`, which the critic packet includes.

- `test10-cover-run.jpg`: test build 10, cover screen, mid-run. First frame
  from the phone. The pebble bed is a regular lattice of ovals: the ground
  shader computed world positions, cell ids and hashes at medium (16-bit)
  precision, which the browser captures never show. Fixed in test build 11
  (highp for coordinates, ids and time; hash inputs wrapped).
