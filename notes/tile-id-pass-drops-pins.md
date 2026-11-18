# A plugged monitor's pins can drop silently

Decision: monitor setups. Recorded 2026-11-17 16:52 CST.

In id mode, a plugged monitor with no grid under its id skips its pass at tile.ps1:581 (`else { continue }`). Its hand-written pins are not placed and not listed as missing. Only an unplugged monitor gets a phantom pass, in the branch above it.
