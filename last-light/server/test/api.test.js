import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createClient } from "@libsql/client";
import { handle, DAY_SECONDS } from "../src/app.js";

const schema = readFileSync(new URL("../schema.sql", import.meta.url), "utf8");
const NOW = Date.UTC(2026, 10, 19, 12, 0, 0);
const TODAY = 1; // the permanent island
let db;

beforeEach(async () => {
  db = createClient({ url: ":memory:" });
  await db.executeMultiple(schema);
});

async function call(method, path, { body, token, now = NOW } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const req = new Request(`https://api.test${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const res = await handle(req, {}, db, now);
  return { status: res.status, data: res.status === 204 ? null : await res.json(), headers: res.headers };
}

async function player(name) {
  const { data } = await call("POST", "/api/players", { body: { name } });
  return data;
}

test("health and CORS preflight", async () => {
  assert.equal((await call("GET", "/api/health")).status, 200);
  const pre = await call("OPTIONS", "/api/players");
  assert.equal(pre.status, 204);
  assert.match(pre.headers.get("Access-Control-Allow-Headers"), /Authorization/);
});

test("registers players and cleans names", async () => {
  const p = await player("  Ada\u0000 Lovelace the Very Long Named  ");
  assert.equal(p.name, "Ada Lovelace the Ver");
  assert.match(p.token, /^[0-9a-f]{64}$/);
  const anon = await player("");
  assert.equal(anon.name, "Wanderer");
});

test("rejects missing or bad tokens", async () => {
  assert.equal((await call("POST", "/api/runs", { body: { seed: TODAY } })).status, 401);
  assert.equal((await call("POST", "/api/runs", { body: { seed: TODAY }, token: "f".repeat(64) })).status, 401);
});

test("only the permanent island accepts runs and traces", async () => {
  const p = await player("Ada");
  assert.equal((await call("POST", "/api/runs", { body: { seed: TODAY }, token: p.token })).status, 201);
  // It stays open: a run months later is still accepted.
  const later = NOW + 200 * 86400000;
  assert.equal((await call("POST", "/api/runs", { body: { seed: TODAY }, token: p.token, now: later })).status, 201);
  // Old daily islands are closed to new writes but can still be read.
  assert.equal((await call("POST", "/api/runs", { body: { seed: 20261119 }, token: p.token })).status, 403);
  assert.equal((await call("GET", "/api/islands/20261119/traces")).status, 200);
  for (const bad of ["0", "abc", "123456789", "-1"]) {
    assert.equal((await call("GET", `/api/islands/${bad}/traces`)).status, 400, bad);
  }
});

test("positions across the whole big island are accepted", async () => {
  const p = await player("Ada");
  const far = await call("POST", `/api/islands/${TODAY}/traces`, {
    token: p.token,
    body: { kind: "note", x: 15000, y: 9000, text: "Far north camp" },
  });
  assert.equal(far.status, 201);
  const off = await call("POST", `/api/islands/${TODAY}/traces`, {
    token: p.token,
    body: { kind: "note", x: 16385, y: 1, text: "off the map" },
  });
  assert.equal(off.status, 400);
});

test("notes, camps and stashes show up for other players", async () => {
  const ada = await player("Ada");
  const bo = await player("Bo");
  const note = await call("POST", `/api/islands/${TODAY}/traces`, {
    token: ada.token,
    body: { kind: "note", x: 100, y: 200, text: "Wolves north of the lake" },
  });
  assert.equal(note.status, 201);
  await call("POST", `/api/islands/${TODAY}/traces`, { token: ada.token, body: { kind: "camp", x: 50, y: 60 } });

  const { data } = await call("GET", `/api/islands/${TODAY}/traces`, { token: bo.token });
  assert.equal(data.traces.length, 2);
  const found = data.traces.find((t) => t.kind === "note");
  assert.equal(found.text, "Wolves north of the lake");
  assert.equal(found.player_name, "Ada");

  const empty = await call("POST", `/api/islands/${TODAY}/traces`, {
    token: ada.token,
    body: { kind: "note", x: 1, y: 1, text: "   " },
  });
  assert.equal(empty.status, 400);
  const offMap = await call("POST", `/api/islands/${TODAY}/traces`, {
    token: ada.token,
    body: { kind: "camp", x: 999999, y: 1 },
  });
  assert.equal(offMap.status, 400);
  const grave = await call("POST", `/api/islands/${TODAY}/traces`, {
    token: ada.token,
    body: { kind: "grave", x: 1, y: 1 },
  });
  assert.equal(grave.status, 400, "graves only come from dying");
});

test("each player has a limited number of notes per island", async () => {
  const ada = await player("Ada");
  for (let i = 0; i < 10; i++) {
    const r = await call("POST", `/api/islands/${TODAY}/traces`, {
      token: ada.token,
      body: { kind: "note", x: i, y: i, text: `note ${i}` },
    });
    assert.equal(r.status, 201);
  }
  const over = await call("POST", `/api/islands/${TODAY}/traces`, {
    token: ada.token,
    body: { kind: "note", x: 1, y: 1, text: "one too many" },
  });
  assert.equal(over.status, 429);
});

test("a stash can be taken once, and not by its owner", async () => {
  const ada = await player("Ada");
  const bo = await player("Bo");
  const cy = await player("Cy");
  const made = await call("POST", `/api/islands/${TODAY}/traces`, {
    token: ada.token,
    body: { kind: "stash", x: 10, y: 10, items: { wood: 4, stone: 999, gold: 5, berries: 0 } },
  });
  assert.equal(made.status, 201);
  const id = made.data.id;

  assert.equal((await call("POST", `/api/traces/${id}/take`, { token: ada.token })).status, 403);
  const taken = await call("POST", `/api/traces/${id}/take`, { token: bo.token });
  assert.equal(taken.status, 200);
  assert.deepEqual(taken.data.items, { wood: 4, stone: 50 });
  const again = await call("POST", `/api/traces/${id}/take`, { token: cy.token });
  assert.equal(again.status, 409);
  assert.equal(again.data.error, "already_taken");

  const { data } = await call("GET", `/api/islands/${TODAY}/traces`);
  assert.equal(data.traces.length, 0, "taken stashes disappear");

  const emptyStash = await call("POST", `/api/islands/${TODAY}/traces`, {
    token: ada.token,
    body: { kind: "stash", x: 10, y: 10, items: { gold: 5 } },
  });
  assert.equal(emptyStash.status, 400);
});

test("dying leaves a grave and ranks the leaderboard", async () => {
  const ada = await player("Ada");
  const bo = await player("Bo");
  const runA = (await call("POST", "/api/runs", { body: { seed: TODAY }, token: ada.token })).data.run_id;
  const runB = (await call("POST", "/api/runs", { body: { seed: TODAY }, token: bo.token })).data.run_id;

  const later = NOW + 5 * DAY_SECONDS * 1000;
  const endA = await call("POST", `/api/runs/${runA}/end`, {
    token: ada.token,
    now: later,
    body: { days: 4, x: 300, y: 300, text: "Should have built a fire", cause: "the cold" },
  });
  assert.equal(endA.status, 200);
  assert.equal(endA.data.days, 4);

  // Claims beyond the time actually played are capped.
  const endB = await call("POST", `/api/runs/${runB}/end`, {
    token: bo.token,
    now: later,
    body: { days: 500, x: 10, y: 10, text: "", cause: "wolves" },
  });
  assert.equal(endB.data.days, 6);

  // A run can only end once, and only by its owner.
  assert.equal((await call("POST", `/api/runs/${runA}/end`, { token: ada.token, body: { days: 1, x: 1, y: 1 } })).status, 409);
  assert.equal((await call("POST", `/api/runs/${runB}/end`, { token: ada.token, body: { days: 1, x: 1, y: 1 } })).status, 404);

  const traces = (await call("GET", `/api/islands/${TODAY}/traces`)).data.traces;
  const graves = traces.filter((t) => t.kind === "grave");
  assert.equal(graves.length, 2);
  assert.equal(graves.find((g) => g.player_name === "Ada").text, "Should have built a fire");

  const board = (await call("GET", `/api/islands/${TODAY}/leaderboard`)).data.entries;
  assert.deepEqual(board, [
    { name: "Bo", days: 6 },
    { name: "Ada", days: 4 },
  ]);
});

test("unknown routes and bad JSON", async () => {
  assert.equal((await call("GET", "/api/nope")).status, 404);
  assert.equal((await call("GET", "/")).status, 404);
  const req = new Request("https://api.test/api/players", { method: "POST", body: "{nope" });
  assert.equal((await handle(req, {}, db, NOW)).status, 400);
});
