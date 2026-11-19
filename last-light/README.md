# 🔥 Last Light

A survival game made with Godot, set on a shared island. A new island washes up every day at midnight UTC, and every player gets the same one. You never meet other survivors, but you find what they left: graves with epitaphs, notes, abandoned campfires and stashes of supplies. When you die, your grave stays on the island for everyone who plays that day.

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
- **Leaderboard.** When you die you see the longest survivors on today's island.

Controls: WASD/arrows to move, `E` (hold) to gather or use, `Space`/click to attack, `F` to eat, `H` to show or hide help.

Without a server configured, the game runs offline: the island and survival work, but there are no traces and no leaderboard.

## Layout

```
last-light/
  game/                 Godot 4.4 project (GL Compatibility renderer, so it runs on the web)
    scripts/main.gd       game loop, rules, crafting, day/night, death
    scripts/world.gd      island generated from the daily seed, harvestable props
    scripts/player.gd     stats, inventory, movement
    scripts/campfire.gd   warmth, light, cooking
    scripts/wolf.gd       night predators
    scripts/trace.gd      graves, notes and stashes left by other players
    scripts/hud.gd        interface, built in code
    scripts/api.gd        client for the island server
    tools/smoke_test.gd   headless test run in CI
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

**1. Create the database (Turso CLI)**

```bash
turso db create last-light
```

```bash
turso db shell last-light < last-light/server/schema.sql
```

```bash
turso db show last-light --url
```

```bash
turso db tokens create last-light
```

**2. Deploy the island server (Cloudflare Worker)**

```bash
cd last-light/server && npm install
```

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

- New traces are accepted only on today's island (give or take a day).
- Each player can leave at most 10 notes, 5 stashes and 25 camps per island.
- Positions must be on the map, and text is cleaned and length-limited.
- A stash can be taken once, and not by the person who left it.
- The days you report at death are capped by the real time since your run started.

## Ideas for later

- Save and resume a run in progress.
- More creatures, seasons and weather.
- Show other players' recent deaths as you walk past.
- Real-time co-op on Render (headless Godot server).
