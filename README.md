# ⚔️ Iron Crowns

A turn-based medieval strategy game for the browser. Four kingdoms fight over one realm. Build your economy, raise big armies, raid your rivals and storm their castles.

## Play

Open `index.html` in any modern browser. It's plain HTML, CSS and JavaScript, with no build step and no dependencies.

To host it for free on **GitHub Pages**: go to **Settings → Pages**, set *Source* to **Deploy from a branch**, pick `main` and `/ (root)`, then save. The game will be live at `https://<your-username>.github.io/Army-Medieval-/`.

## How it plays

- **A new map every campaign.** About 40 provinces: castles 🏰, towns 🏘️, villages 🛖, farmland 🌾, forests 🌲 and mines ⛏️.
- **Economy.** Provinces produce gold, food and wood each turn. Armies eat food; if your granaries run dry, soldiers desert. Develop ⭐ provinces to raise their yields.
- **Armies.** Recruit militia, spearmen, archers, knights and catapults in castles and towns. Spearmen beat knights, knights beat archers, archers beat spearmen.
- **Raids.** Send a party to loot an enemy province and part of their treasury. The province is burned and earns nothing for 3 turns, and your raiders come home.
- **Sieges.** Walls 🧱 strengthen defenders and call up levy. Catapults break walls.
- **Battles** resolve automatically. You watch them play out with hundreds of soldiers on the field.
- **Three computer-controlled kingdoms** expand, recruit, raid and fight each other and you. Difficulty: Squire, Knight or Warlord.
- **Win** by capturing every rival capital 👑. Lose your own capital and your reign ends.
- Your campaign is saved automatically in the browser.

Shortcuts: **E** ends the turn, **Esc** deselects.

## Files

- `index.html`: page layout
- `style.css`: styling
- `game.js`: map generation, rules, battle system, computer opponents, rendering and UI

## Also in this repository

- [`last-light/`](last-light/): **Islander**, a Godot survival game on a shared daily island, with a Cloudflare Worker + Turso server. See its [README](last-light/README.md).
