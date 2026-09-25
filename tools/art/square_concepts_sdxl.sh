#!/usr/bin/env bash
# Square concept images with a free local model (stable-diffusion.cpp + SDXL 1.0, CreativeML Open
# RAIL++-M). Prompts use only the game's own content (docs/design/content_v0.3/01_world, locations.json):
# Fourleaf Hollow, the fountain with the four suits, Sera's shop, the player's home, the card room,
# the village hall, the notice board, the festival booth, fire-seed lamps, Lumi, Moa, Juno.
#   SD_DIR=C:/Users/a/tools/sdcpp bash tools/art/square_concepts_sdxl.sh [out_dir]
set -e
SD_DIR="${SD_DIR:-/c/Users/a/tools/sdcpp}"
OUT="${1:-docs/art_direction/square_concepts_free}"
mkdir -p "$OUT"

# SDXL reads about 77 tokens: style first, then the few things that make the square ours.
BASE="cozy fantasy village square seen from above, big round stone fountain in the center with heart clover diamond spade carvings, cottages around it, one with a club sign, striped shop awning, notice board, lanterns, fox girl and tiny fairy"
NEG="text, letters, words, watermark, logo, signature, casino, neon, slot machine, gambling, photo, photorealistic, \
blurry, lowres, deformed, cropped, frame, border"

gen() {  # name seed prompt
  "$SD_DIR/sd-cli.exe" -m "$SD_DIR/sdxl-base-q4_0.gguf" --vae "$SD_DIR/sdxl_vae_fp16fix.safetensors" \
    -p "$3" -n "$NEG" -W 1344 -H 768 --steps 28 --cfg-scale 6.5 --sampling-method dpm++2m --scheduler karras \
    -s "$2" --vae-tiling -o "$OUT/$1.png"
}

gen 1_storybook_day 11 "hand painted storybook game art, sunny afternoon, $BASE"
gen 2_festival_evening 23 "night festival, warm string lights, glowing windows, blue dusk, painted game art, $BASE"
gen 3_playing_card_print 37 "ornate playing card illustration, flat red cream navy green colors, bold ink lines, symmetric, $BASE"
gen 4_felt_and_chips 41 "toy-like game art, green felt lawns, plaza shaped like a giant poker chip, cheerful colors, $BASE"
gen 5_papercraft 53 "papercraft pop-up book, layered cut paper, paper texture, soft shadows, $BASE"
gen 6_woodcut_evening 67 "woodblock print, carved lines, few flat colors, evening lantern glow, $BASE"
