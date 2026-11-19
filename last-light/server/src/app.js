// Last Light island server: request handling, independent of where the database lives.
// src/index.js wires this to Turso inside a Cloudflare Worker; the tests use a local database.

export const DAY_SECONDS = 240; // must match DAY_LENGTH in game/scripts/main.gd
export const WORLD_PX = 1024 * 16; // island size in pixels (World.SIZE * World.TILE)
// Islands that accept new runs and traces. The game uses one permanent island.
export const OPEN_ISLANDS = new Set([1]);
export const LIMITS = { note: 10, stash: 5, camp: 25 }; // per player, per island
export const ITEMS = ["wood", "stone", "berries", "cooked_meat"];
const MAX_BODY = 4096;
const MAX_SAVE = 1_000_000; // characters of save JSON per player
const MAX_TRACES = 300;
// PBKDF2 rounds for passwords. Kept moderate so a login fits in a Worker's CPU budget.
export const PASSWORD_ITERATIONS = 20000;
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const LOGIN_MAX_FAILURES = 10;

// Tables added after the first release. Created on demand so an existing
// database keeps working without re-running schema.sql.
const LATER_TABLES = `
CREATE TABLE IF NOT EXISTS accounts (
  player_id     TEXT PRIMARY KEY REFERENCES players(id),
  username      TEXT NOT NULL,
  username_key  TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  salt          TEXT NOT NULL,
  iterations    INTEGER NOT NULL,
  created_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash  TEXT PRIMARY KEY,
  player_id   TEXT NOT NULL REFERENCES players(id),
  created_at  INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS saves (
  player_id   TEXT PRIMARY KEY REFERENCES players(id),
  data        TEXT NOT NULL,
  saved_at    REAL NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS login_failures (
  username_key TEXT NOT NULL,
  at           INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS login_failures_key ON login_failures (username_key, at);
`;
const schemaReady = new WeakMap();
function ensureSchema(db) {
  if (!schemaReady.has(db)) {
    schemaReady.set(db, db.executeMultiple(LATER_TABLES).catch((err) => {
      schemaReady.delete(db);
      throw err;
    }));
  }
  return schemaReady.get(db);
}

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
    "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS",
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
    await ensureSchema(db);
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
      case "POST account":
        return json(201, await createAccount(ctx));
      case "GET account":
        return json(200, await getAccount(ctx));
      case "POST login":
        return json(200, await login(ctx));
      case "GET save":
        return json(200, await getSave(ctx));
      case "PUT save":
        return json(200, await putSave(ctx));
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
  const seed = writableSeed(body.seed);
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
  const seed = writableSeed(seedParam);
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

// ---------- Accounts and cloud saves ----------

// Gives the current (so far anonymous) player a username and password, so they
// can log in from any browser.
async function createAccount(ctx) {
  const player = await auth(ctx);
  const body = await readBody(ctx);
  const username = String(body.username ?? "").trim();
  const password = String(body.password ?? "");
  if (!/^[A-Za-z0-9_-]{3,20}$/.test(username)) throw new HttpError(400, "bad_username");
  if (password.length < 8 || password.length > 100) throw new HttpError(400, "bad_password");

  const existing = await ctx.db.execute({
    sql: "SELECT username FROM accounts WHERE player_id = ?",
    args: [player.id],
  });
  if (existing.rows[0]) throw new HttpError(409, "already_has_account");

  const salt = randomHex(16);
  const hash = await hashPassword(password, salt, PASSWORD_ITERATIONS);
  try {
    await ctx.db.execute({
      sql: `INSERT INTO accounts (player_id, username, username_key, password_hash, salt, iterations, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)`,
      args: [player.id, username, username.toLowerCase(), hash, salt, PASSWORD_ITERATIONS, ctx.now],
    });
  } catch (err) {
    if (/UNIQUE/i.test(String(err?.message))) throw new HttpError(409, "username_taken");
    throw err;
  }
  return { username };
}

async function getAccount(ctx) {
  const player = await auth(ctx);
  const rs = await ctx.db.execute({ sql: "SELECT username FROM accounts WHERE player_id = ?", args: [player.id] });
  return { id: player.id, name: player.name, username: rs.rows[0]?.username ?? null };
}

async function login(ctx) {
  const body = await readBody(ctx);
  const key = String(body.username ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");
  if (!key || !password) throw new HttpError(400, "missing_login");

  const recent = await ctx.db.execute({
    sql: "SELECT COUNT(*) AS n FROM login_failures WHERE username_key = ? AND at > ?",
    args: [key, ctx.now - LOGIN_WINDOW_MS],
  });
  if (Number(recent.rows[0].n) >= LOGIN_MAX_FAILURES) throw new HttpError(429, "too_many_attempts");

  const rs = await ctx.db.execute({
    sql: `SELECT a.player_id, a.username, a.password_hash, a.salt, a.iterations, p.name
          FROM accounts a JOIN players p ON p.id = a.player_id WHERE a.username_key = ?`,
    args: [key],
  });
  const account = rs.rows[0];
  const ok = account
    ? sameText(await hashPassword(password, account.salt, Number(account.iterations)), account.password_hash)
    : false;
  if (!ok) {
    await ctx.db.execute({ sql: "INSERT INTO login_failures (username_key, at) VALUES (?, ?)", args: [key, ctx.now] });
    throw new HttpError(401, "wrong_login");
  }

  const token = randomHex(32);
  await ctx.db.batch(
    [
      {
        sql: "INSERT INTO sessions (token_hash, player_id, created_at) VALUES (?, ?, ?)",
        args: [await sha256(token), account.player_id, ctx.now],
      },
      { sql: "DELETE FROM login_failures WHERE username_key = ?", args: [key] },
    ],
    "write",
  );
  return { id: account.player_id, name: account.name, username: account.username, token };
}

async function getSave(ctx) {
  const player = await auth(ctx);
  const rs = await ctx.db.execute({
    sql: "SELECT data, saved_at FROM saves WHERE player_id = ?",
    args: [player.id],
  });
  const row = rs.rows[0];
  return row ? { saved_at: Number(row.saved_at), save: JSON.parse(row.data) } : { saved_at: 0, save: null };
}

async function putSave(ctx) {
  const player = await auth(ctx);
  const body = await readBody(ctx, MAX_SAVE + 1000);
  const savedAt = Number(body.saved_at);
  if (!Number.isFinite(savedAt) || savedAt <= 0) throw new HttpError(400, "bad_saved_at");
  if (!body.save || typeof body.save !== "object" || Array.isArray(body.save)) throw new HttpError(400, "bad_save");
  const data = JSON.stringify(body.save);
  if (data.length > MAX_SAVE) throw new HttpError(413, "save_too_large");

  // Never replace a save with an older one (say, from a tab left open elsewhere).
  const result = await ctx.db.execute({
    sql: `INSERT INTO saves (player_id, data, saved_at, updated_at) VALUES (?, ?, ?, ?)
          ON CONFLICT (player_id) DO UPDATE SET data = excluded.data, saved_at = excluded.saved_at,
            updated_at = excluded.updated_at
          WHERE excluded.saved_at >= saves.saved_at`,
    args: [player.id, data, savedAt, ctx.now],
  });
  if (result.rowsAffected === 0) throw new HttpError(409, "newer_save_exists");
  return { ok: true, saved_at: savedAt };
}

async function hashPassword(password, saltHex, iterations) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, [
    "deriveBits",
  ]);
  const salt = new Uint8Array(saltHex.match(/../g).map((h) => parseInt(h, 16)));
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations }, key, 256);
  return [...new Uint8Array(bits)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Compares two strings in constant time.
function sameText(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ---------- Helpers ----------

async function auth(ctx) {
  const header = ctx.request.headers.get("Authorization") || "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!/^[0-9a-f]{64}$/.test(token)) throw new HttpError(401, "unauthorized");
  const hash = await sha256(token);
  // A token is either the one a player got when they first played, or one from logging in.
  const rs = await ctx.db.execute({
    sql: `SELECT id, name FROM players WHERE token_hash = ?
          UNION ALL
          SELECT p.id, p.name FROM sessions s JOIN players p ON p.id = s.player_id WHERE s.token_hash = ?
          LIMIT 1`,
    args: [hash, hash],
  });
  if (!rs.rows[0]) throw new HttpError(401, "unauthorized");
  return { id: rs.rows[0].id, name: rs.rows[0].name };
}

async function readBody(ctx, max = MAX_BODY) {
  if (ctx.body) return ctx.body;
  const text = await ctx.request.text();
  if (text.length > max) throw new HttpError(413, "too_large");
  if (!text) return (ctx.body = {});
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
    return (ctx.body = parsed);
  } catch {
    throw new HttpError(400, "bad_json");
  }
}

// An island id: a positive whole number. Old daily islands (20261119) can still be read.
export function parseSeed(value) {
  const s = String(value ?? "");
  if (!/^[1-9]\d{0,7}$/.test(s)) throw new HttpError(400, "bad_seed");
  return Number(s);
}

// Only open islands accept new runs and traces.
export function writableSeed(value) {
  const seed = parseSeed(value);
  if (!OPEN_ISLANDS.has(seed)) throw new HttpError(403, "island_closed");
  return seed;
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
