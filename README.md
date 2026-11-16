# ⚔️ Iron Crowns

A turn-based medieval strategy game for the browser, in 3D. Four kingdoms fight over one realm. Build your economy, raise big armies, raid your rivals, play them against each other through diplomacy, and storm their castles.

## Play

The game needs a web server for its 3D views. Two ways to run it:

- **GitHub Pages (recommended):** go to **Settings → Pages**, set *Source* to **Deploy from a branch**, pick `main` and `/ (root)`, then save. The game will be live at `https://<your-username>.github.io/Army-Medieval-/`.
- **Locally:** run `python3 -m http.server` in this folder and open <http://localhost:8000>.

If you open `index.html` straight from disk, or the browser has no WebGL, the game still runs on its flat 2D map with 2D battles.

## Features

### 3D campaign map
- A new map every campaign: terrain with hills, mountains around mines, forests, farmland and a coast with moving water.
- Low-poly castles, towns, villages, windmills and mines. Walls appear as you build them, and pillaged provinces burn and smoke.
- Armies stand on the map with their banners and visibly march between provinces, both yours and the computer's.
- Time of day changes each turn, from dawn to night.
- Controls: drag to pan, right-drag to rotate, scroll to zoom. On touch screens: drag, pinch and rotate with two fingers. The **🗺 2D** button switches to the flat map.

### 3D battles
- Every battle is played out with hundreds of soldiers. Spearmen, militia, archers, mounted knights, catapults and levy each have their own model.
- Archers loose volleys in arcs, knights charge on the flanks, the lines clash and the dead fall.
- Sieges have stone walls with towers. Defending archers shoot from the walls, and catapult stones knock the walls down.
- The battlefield matches the province: wheat fields, forest, rocky mine country, or the town or castle behind the defenders.
- A cinematic camera you can take over at any time by dragging. **Skip** jumps to the result.

### Strategy
- **Economy:** gold, food and wood. Armies eat food; if it runs out, soldiers desert. Develop provinces to raise their yields.
- **Units:** spearmen beat knights, knights beat archers, archers beat spearmen. Catapults break walls.
- **Raids:** loot a province and part of its owner's treasury, burn it for 3 turns, and bring your raiders home.
- **Generals:** hire them in castles. A general adds +6% strength per level to the army they lead and levels up by fighting. Generals can be slain or captured.
- **Veterancy:** armies gain experience in battle, rising from Recruits to Seasoned, Veterans and ★★★ Elite (up to +20%).
- **Fog of war** (optional): enemy armies are hidden beyond your borders. Generals and level 2 walls see further, and allies share their sight.
- **Diplomacy:** send gifts, sign truces and alliances, demand tribute or declare war. Computer kingdoms remember how you treat them, send you their own offers, and band together against whoever is strongest.
- **Three computer-controlled kingdoms** that expand, recruit, hire generals, raid, besiege and negotiate. Difficulty: Squire, Knight or Warlord.
- **Win** by capturing every rival capital. Lose your own capital and your reign ends. The campaign saves automatically in your browser.

Shortcuts: **E** ends the turn, **D** opens diplomacy, **Esc** deselects.

## Files

- `index.html`: page layout and the import map for [Three.js](https://threejs.org) (loaded from a CDN)
- `style.css`: styling
- `game.js`: rules engine, map generation, computer kingdoms, diplomacy, UI, and the 2D map and battle fallbacks
- `map3d.js`: the 3D campaign map
- `battle3d.js`: the 3D battle viewer
- `models.js`: low-poly models (soldiers, buildings, trees) shared by both 3D views
