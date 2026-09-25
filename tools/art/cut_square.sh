#!/usr/bin/env bash
# Rebuilds art_src/square/cut from the AI-generated sheets in art_src/square/raw
# (then run: python tools/art/build_square_art.py).
set -e
cd "$(dirname "$0")/../../art_src/square"
mkdir -p cut
C=../../tools/art/cut_sheet.py
for s in sheet_street sheet_plants sheet_misc sheet_story; do python $C raw/$s.png cut/$s --rows 2 --grow 4; done
for c in player lumi moa juno bibi miri; do python $C raw/ch_$c.png cut/ch_$c --grid 5x1 --grow 6; done
for p in player lumi moa juno; do python $C raw/pt_$p.png cut/pt_$p --grid 3x1 --grow 8; done
python $C raw/pt_bibi_miri.png cut/pt_bm --grid 3x2 --grow 6
python $C raw/ui_kit.png cut/ui --rows 3 --grow 2 --min-area 800
