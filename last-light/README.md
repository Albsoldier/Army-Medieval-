# 🔥 Last Light

A low-poly 3D survival game made with Godot, set on one big, permanent island (about a kilometre across) that every player shares. You never meet other survivors, but you find what they left: graves with epitaphs, notes, abandoned campfires and stashes of supplies. When you die, your grave stays on the island for good.

Your progress is saved: your survivor, inventory, campfires and every tree you've cut. The game saves in your browser every few seconds and backs up to the island server every 15 seconds (and at dawn, on death, on Save now and when you leave the page). Create an account (Esc → Account) to log in from any browser or device and continue where you left off. Whichever copy is newer wins, so an old tab can't overwrite newer progress.

## How it plays

- **Survive.** Keep **health, hunger, warmth and sanity** above zero. One in-game day lasts 4 minutes, and about a third of it is night.
- **Gather.** Chop trees for wood, break rocks for stone and pick berries. Bushes grow back after two days.
- **Craft.** `1` campfire (5 wood, 3 stone), `2` torch (2 wood), `3` spear (3 wood, 2 stone).
- **Nights are dangerous.** It gets cold and dark, and wolves come out. Wolves won't go near firelight. Kill them for meat and cook it at a fire.
- **Other survivors' traces.**
  - Reading a **note** or a **grave** restores sanity.
  - A cold **campfire** left by someone else can be relit with 2 wood.
  - The first person to open a **stash** gets what's inside.
  - Press `N` to leave a note and `G` to leave half your supplies as a stash.
- **Death costs you nothing permanent.** You wake at your last campfire, and what you carried waits in a bag where you fell.
- **The island recovers.** Felled trees, broken rocks and picked bushes grow back after a few days.
- **Leaderboard.** When you die you see the longest lives on the island.
- **Pause menu (Esc):** save now, or start over with a fresh save.
- **Build a base (B).** Aim with the mouse and click (or E) to build, X to demolish for half the materials back:

  | Key | Structure | Cost | What it does |
  |---|---|---|---|
  | 1 | Wooden wall | 4 wood | Blocks wolves; they gnaw through it slowly at night |
  | 2 | Stone wall | 3 stone, 1 wood | 2.5× tougher, gnawed 3× slower |
  | 3 | Gate | 6 wood | You and your soldiers pass, wolves don't |
  | 4 | Torch post | 2 wood, 1 stone | Permanent light; wolves keep away, eases your mind |
  | 5 | Storage chest | 8 wood | Store and take items |
  | 6 | Tent | 10 wood, 3 berries | Wake here after dying; sleep through the night |
  | 7 | Barracks | 20 wood, 10 stone | Houses 10 soldiers |

  Press E at a damaged wall to repair it.
- **Raise an army.** At a barracks, recruit soldiers for 3 wood, 2 stone and 5 berries each: up to 10 per barracks and 100 in all. Soldiers fight wolves (you get the meat), and wolves fight back. Press T to switch between *follow me* (rows behind you) and *guard here* (rings around the spot).

Controls: WASD/arrows to move, mouse wheel to zoom, `E` (hold) to gather or use, `Space`/click to attack, `F` to eat, `H` to show or hide help.

Without a server configured, the game runs offline: the island and survival work, but there are no traces and no leaderboard.

## Layout

```
last-light/
  game/                 Godot 4.4 project (GL Compatibility renderer, so it runs on the web)
    scripts/main.gd       game loop, rules, crafting, day/night, death
    scripts/world.gd      the permanent island, generated and drawn in chunks around you
    scripts/save_game.gd  the save file (stored in the browser)
    scripts/structure.gd  walls, gates, torch posts, chests, tents and barracks
    scripts/soldier.gd    your soldiers: following, guarding and fighting
    scripts/art.gd        helpers for the low-poly models
    scripts/character_model.gd  loads, sizes and animates the rigged characters
    models/               survivor and wolf models (CC0, by Quaternius: see models/CREDITS.md)
    scripts/player.gd     stats, inventory, movement
    scripts/campfire.gd   warmth, light, cooking
    scripts/wolf.gd       night predators
    scripts/trace.gd      graves, notes and stashes left by other players
    scripts/hud.gd        interface, built in code
    scripts/api.gd        client for the island server
    tools/smoke_test.gd   headless test run in CI
    tools/screenshot.gd   renders screenshots in CI (see the ci/last-light-screenshots branch)
  server/               Cloudflare Worker + Turso (the "island server")
    src/app.js            API routes and rules
    src/index.js          Worker entry point
    schema.sql            database tables
    test/                 API tests (node --test, local libSQL)
.github/workflows/last-light.yml   tests, web export, deploy
```

## Which service does what

| Service | Job |
|---|---|
| **Godot** | The game. CI exports it to the web. |
| **GitHub** | Code. Actions runs tests, exports the game and deploys it. |
| **Cloudflare Pages** | Hosts the web build. |
| **Cloudflare Workers** | The island server API (`server/`). |
| **Turso** | Database for players, runs and traces. |
| **Render** | Not needed for this design. Keep it for a real-time co-op mode later. |

## Set up (one time)

**1. Create the database**

On the Turso website (app.turso.tech), create a database named `last-light`. Copy its URL (`libsql://...`) and create a token for it. Then create the tables from `last-light/server`. In PowerShell:

```powershell
npm install
$env:TURSO_DATABASE_URL="libsql://your-db-url"
$env:TURSO_AUTH_TOKEN="your-token"
npm run db:setup
```

On macOS or Linux with the Turso CLI, you can instead run `turso db shell last-light < schema.sql`.

**2. Deploy the island server (Cloudflare Worker)**

```bash
npx wrangler secret put TURSO_DATABASE_URL
```

```bash
npx wrangler secret put TURSO_AUTH_TOKEN
```

```bash
npx wrangler deploy
```

Wrangler prints the Worker URL, for example `https://last-light-api.<you>.workers.dev`. Open `/api/health` on it to check it works.

**3. Connect GitHub to Cloudflare.** In the repository's **Settings → Secrets and variables → Actions**:

- Add a **secret** `CLOUDFLARE_API_TOKEN`: a Cloudflare API token with *Workers Scripts: Edit* and *Cloudflare Pages: Edit* permissions.
- Add a **secret** `CLOUDFLARE_ACCOUNT_ID`: your Cloudflare account ID.
- Add a **variable** `LAST_LIGHT_API_URL`: the Worker URL from step 2.

After that, every push to `main` that changes `last-light/` runs the tests, exports the game and deploys both the server and the game. The game goes live at `https://last-light.pages.dev`, or on a similar address if that name is taken. If the secrets aren't set, the deploy step is skipped and the web build is still saved as a workflow artifact.

## Develop locally

- **Game:** open `last-light/game/project.godot` in Godot 4.4 or newer and press F5. To use a server, set **Project Settings → Last Light → Api → Base Url**. A web build also accepts `?api=https://...` in the page URL. Run with `-- --seed=20261119` to load a specific island.
- **Server:** run `npm test` in `last-light/server`. For a live local server, put `TURSO_DATABASE_URL` and `TURSO_AUTH_TOKEN` in `last-light/server/.dev.vars` and run `npm run dev`.

## Fair play

The server checks what it can:

- New runs and traces are accepted only on the permanent island (id 1). Old daily islands can still be read.
- Each player can leave at most 10 notes, 5 stashes and 25 camps per island.
- Positions must be on the map, and text is cleaned and length-limited.
- A stash can be taken once, and not by the person who left it.
- The days you report at death are capped by the real time since your run started.

## Ideas for later

- Save and resume a run in progress.
- More creatures, seasons and weather.
- Show other players' recent deaths as you walk past.
- Real-time co-op on Render (headless Godot server).
