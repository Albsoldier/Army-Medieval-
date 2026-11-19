// Last Light island server: request handling, independent of where the database lives.
// src/index.js wires this to Turso inside a Cloudflare Worker; the tests use a local database.

export const DAY_SECONDS = 240; // must match DAY_LENGTH in game/scripts/main.gd
export const WORLD_PX = 160 * 16; // island size in pixels (World.SIZE * World.TILE)
export const LIMITS = { note: 10, stash: 5, camp: 25 }; // per player, per island
export const ITEMS = ["wood", "stone", "berries", "cooked_meat"];
const MAX_BODY = 4096;
const MAX_TRACES = 300;

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

export async function handle(request, env, db, now = Date.now()) {
  const cors = {
    "Access-Control-Allow-Origin": env.ALLOWED_ORIGIN || "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400",
  };
  const json = (status, data) =>
    new Response(JSON.stringify(data), {
      status,
      headers: { ...cors, "Content-Type": "application/json" },
    });

  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });

  const ctx = { request, db, now };
  const path = new URL(request.url).pathname.replace(/\/+$/, "");
  const parts = path.split("/").filter(Boolean); // ["api", ...]

  try {
    if (parts[0] !== "api") throw new HttpError(404, "not_found");
    const [, a, b, c] = parts;
    const route = `${request.method} ${a ?? ""}${b ? "/:b" : ""}${c ? "/" + c : ""}`;
    switch (route) {
      case "GET health":
        return json(200, { ok: true });
      case "POST players":
        return json(201, await createPlayer(ctx));
      case "POST runs":
        return json(201, await startRun(ctx));
      case "POST runs/:b/end":
        return json(200, await endRun(ctx, b));
      case "GET islands/:b/traces":
        return json(200, await listTraces(ctx, b));
      case "POST islands/:b/traces":
        return json(201, await createTrace(ctx, b));
      case "POST traces/:b/take":
        return json(200, await takeStash(ctx, b));
      case "GET islands/:b/leaderboard":
        return json(200, await leaderboard(ctx, b));
      default:
        throw new HttpError(404, "not_found");
    }
  } catch (err) {
    if (err instanceof HttpError) return json(err.status, { error: err.code });
    console.error(err);
    return json(500, { error: "server_error" });
  }
}

// ---------- Handlers ----------

async function createPlayer(ctx) {
  const body = await readBody(ctx);
  const name = cleanText(body.name, 20) || "Wanderer";
  const id = crypto.randomUUID();
  const token = randomHex(32);
  await ctx.db.execute({
    sql: "INSERT INTO players (id, name, token_hash, created_at) VALUES (?, ?, ?, ?)",
    args: [id, name, await sha256(token), ctx.now],
  });
  return { id, name, token };
}

async function startRun(ctx) {
  const player = await auth(ctx);
  const body = await readBody(ctx);
  const seed = writableSeed(body.seed, ctx.now);
  const id = crypto.randomUUID();
  await ctx.db.execute({
    sql: "INSERT INTO runs (id, player_id, seed, started_at) VALUES (?, ?, ?, ?)",
    args: [id, player.id, seed, ctx.now],
  });
  return { run_id: id, started_at: ctx.now };
}

async function endRun(ctx, runId) {
  const player = await auth(ctx);
  const body = await readBody(ctx);
  const rs = await ctx.db.execute({
    sql: "SELECT id, seed, started_at, ended_at FROM runs WHERE id = ? AND player_id = ?",
    args: [runId, player.id],
  });
  const run = rs.rows[0];
  if (!run) throw new HttpError(404, "run_not_found");
  if (run.ended_at !== null) throw new HttpError(409, "run_already_ended");

  // A client can't claim more days than could have passed since the run started.
  const elapsedDays = Math.floor((ctx.now - Number(run.started_at)) / 1000 / DAY_SECONDS);
  const claimed = clampInt(body.days, 0, 10000);
  const days = Math.min(claimed, elapsedDays + 1);
  const { x, y } = position(body);
  const epitaph = cleanText(body.text, 100);
  const cause = cleanText(body.cause, 40);

  await ctx.db.batch(
    [
      {
        sql: "UPDATE runs SET ended_at = ?, days = ?, cause = ? WHERE id = ? AND ended_at IS NULL",
        args: [ctx.now, days, cause, run.id],
      },
      {
        sql: `INSERT INTO traces (id, seed, kind, player_id, player_name, x, y, text, days, created_at)
              VALUES (?, ?, 'grave', ?, ?, ?, ?, ?, ?, ?)`,
        args: [crypto.randomUUID(), run.seed, player.id, player.name, x, y, epitaph, days, ctx.now],
      },
    ],
    "write",
  );
  return { ok: true, days };
}

async function listTraces(ctx, seedParam) {
  const seed = parseSeed(seedParam);
  const rs = await ctx.db.execute({
    sql: `SELECT id, kind, player_id, player_name, x, y, text, items, days, created_at
          FROM traces
          WHERE seed = ? AND (kind != 'stash' OR taken_by IS NULL)
          ORDER BY created_at DESC LIMIT ?`,
    args: [seed, MAX_TRACES],
  });
  const traces = rs.rows.map((r) => ({
    id: r.id,
    kind: r.kind,
    player_id: r.player_id,
    player_name: r.player_name,
    x: Number(r.x),
    y: Number(r.y),
    text: r.text,
    items: r.items ? JSON.parse(r.items) : undefined,
    days: r.days === null ? undefined : Number(r.days),
    created_at: Number(r.created_at),
  }));
  return { seed, traces };
}

async function createTrace(ctx, seedParam) {
  const player = await auth(ctx);
  const seed = writableSeed(seedParam, ctx.now);
  const body = await readBody(ctx);
  const kind = body.kind;
  if (!Object.hasOwn(LIMITS, kind)) throw new HttpError(400, "bad_kind");
  const { x, y } = position(body);

  let text = "";
  let items = null;
  if (kind === "note") {
    text = cleanText(body.text, 140);
    if (!text) throw new HttpError(400, "empty_note");
  } else if (kind === "stash") {
    items = cleanItems(body.items);
  }

  const used = await ctx.db.execute({
    sql: "SELECT COUNT(*) AS n FROM traces WHERE player_id = ? AND seed = ? AND kind = ?",
    args: [player.id, seed, kind],
  });
  if (Number(used.rows[0].n) >= LIMITS[kind]) throw new HttpError(429, "limit_reached");

  const id = crypto.randomUUID();
  await ctx.db.execute({
    sql: `INSERT INTO traces (id, seed, kind, player_id, player_name, x, y, text, items, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    args: [id, seed, kind, player.id, player.name, x, y, text, items && JSON.stringify(items), ctx.now],
  });
  return { id };
}

async function takeStash(ctx, traceId) {
  const player = await auth(ctx);
  const rs = await ctx.db.execute({
    sql: "SELECT id, player_id, items FROM traces WHERE id = ? AND kind = 'stash'",
    args: [traceId],
  });
  const stash = rs.rows[0];
  if (!stash) throw new HttpError(404, "not_found");
  if (stash.player_id === player.id) throw new HttpError(403, "own_stash");

  // Only one survivor gets it: the update succeeds for whoever arrives first.
  const update = await ctx.db.execute({
    sql: "UPDATE traces SET taken_by = ?, taken_at = ? WHERE id = ? AND taken_by IS NULL",
    args: [player.id, ctx.now, traceId],
  });
  if (update.rowsAffected === 0) throw new HttpError(409, "already_taken");
  return { items: JSON.parse(stash.items || "{}") };
}

async function leaderboard(ctx, seedParam) {
  const seed = parseSeed(seedParam);
  const rs = await ctx.db.execute({
    sql: `SELECT p.name AS name, MAX(r.days) AS days
          FROM runs r JOIN players p ON p.id = r.player_id
          WHERE r.seed = ? AND r.days IS NOT NULL
          GROUP BY r.player_id
          ORDER BY days DESC, MIN(r.ended_at) ASC
          LIMIT 20`,
    args: [seed],
  });
  return { seed, entries: rs.rows.map((r) => ({ name: r.name, days: Number(r.days) })) };
}

// ---------- Helpers ----------

async function auth(ctx) {
  const header = ctx.request.headers.get("Authorization") || "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!/^[0-9a-f]{64}$/.test(token)) throw new HttpError(401, "unauthorized");
  const rs = await ctx.db.execute({
    sql: "SELECT id, name FROM players WHERE token_hash = ?",
    args: [await sha256(token)],
  });
  if (!rs.rows[0]) throw new HttpError(401, "unauthorized");
  return { id: rs.rows[0].id, name: rs.rows[0].name };
}

async function readBody(ctx) {
  if (ctx.body) return ctx.body;
  const text = await ctx.request.text();
  if (text.length > MAX_BODY) throw new HttpError(413, "too_large");
  if (!text) return (ctx.body = {});
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
    return (ctx.body = parsed);
  } catch {
    throw new HttpError(400, "bad_json");
  }
}

// Islands are named by their UTC date: 20261119.
export function parseSeed(value) {
  const s = String(value ?? "");
  if (!/^\d{8}$/.test(s)) throw new HttpError(400, "bad_seed");
  const date = seedDate(Number(s));
  if (Number.isNaN(date.getTime()) || dateSeed(date) !== Number(s)) throw new HttpError(400, "bad_seed");
  return Number(s);
}

// Only today's island (give or take a day for time zones and runs past midnight) accepts new traces.
export function writableSeed(value, now) {
  const seed = parseSeed(value);
  const diffDays = Math.abs(seedDate(seed).getTime() - seedDate(dateSeed(new Date(now))).getTime()) / 86400000;
  if (diffDays > 1) throw new HttpError(403, "island_closed");
  return seed;
}

function seedDate(seed) {
  const y = Math.floor(seed / 10000);
  const m = Math.floor(seed / 100) % 100;
  const d = seed % 100;
  return new Date(Date.UTC(y, m - 1, d));
}

export function dateSeed(date) {
  return date.getUTCFullYear() * 10000 + (date.getUTCMonth() + 1) * 100 + date.getUTCDate();
}

function position(body) {
  const x = Number(body.x);
  const y = Number(body.y);
  if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0 || x > WORLD_PX || y > WORLD_PX) {
    throw new HttpError(400, "bad_position");
  }
  return { x: Math.round(x), y: Math.round(y) };
}

function cleanItems(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new HttpError(400, "bad_items");
  const items = {};
  for (const key of ITEMS) {
    if (value[key] === undefined) continue;
    const n = clampInt(value[key], 0, 50);
    if (n > 0) items[key] = n;
  }
  if (Object.keys(items).length === 0) throw new HttpError(400, "empty_stash");
  return items;
}

export function cleanText(value, max) {
  return String(value ?? "")
    .replace(/[\u0000-\u001f\u007f​-‏‪-‮]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, max);
}

function clampInt(value, min, max) {
  const n = Math.floor(Number(value));
  if (!Number.isFinite(n)) return min;
  return Math.min(Math.max(n, min), max);
}

function randomHex(bytes) {
  const buf = crypto.getRandomValues(new Uint8Array(bytes));
  return [...buf].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
