import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createClient } from "@libsql/client";
import { handle } from "../src/app.js";

// Only the original tables: the new ones must be created by the Worker itself.
const firstSchema = readFileSync(new URL("../schema.sql", import.meta.url), "utf8").split("-- Accounts and cloud saves")[0];
const NOW = Date.UTC(2026, 10, 19, 12, 0, 0);
let db;

beforeEach(async () => {
  db = createClient({ url: ":memory:" });
  await db.executeMultiple(firstSchema);
});

async function call(method, path, { body, token, now = NOW, raw } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const req = new Request(`https://api.test${path}`, {
    method,
    headers,
    body: raw ?? (body === undefined ? undefined : JSON.stringify(body)),
  });
  const res = await handle(req, {}, db, now);
  return { status: res.status, data: await res.json() };
}

async function newPlayer(name = "Ada") {
  return (await call("POST", "/api/players", { body: { name } })).data;
}

const SAVE = { version: 1, day: 7, player: { inventory: { wood: 12 } }, props: { "500,510": ["stump", 0, 12] } };

test("an anonymous player's save is kept on the server", async () => {
  const p = await newPlayer();
  assert.deepEqual((await call("GET", "/api/save", { token: p.token })).data, { saved_at: 0, save: null });
  const put = await call("PUT", "/api/save", { token: p.token, body: { saved_at: 1000.5, save: SAVE } });
  assert.equal(put.status, 200);
  const got = await call("GET", "/api/save", { token: p.token });
  assert.equal(got.data.saved_at, 1000.5);
  assert.deepEqual(got.data.save, SAVE);
});

test("an older save never replaces a newer one", async () => {
  const p = await newPlayer();
  await call("PUT", "/api/save", { token: p.token, body: { saved_at: 2000, save: { ...SAVE, day: 9 } } });
  const stale = await call("PUT", "/api/save", { token: p.token, body: { saved_at: 1500, save: SAVE } });
  assert.equal(stale.status, 409);
  assert.equal(stale.data.error, "newer_save_exists");
  assert.equal((await call("GET", "/api/save", { token: p.token })).data.save.day, 9);
});

test("saves are checked for shape and size", async () => {
  const p = await newPlayer();
  assert.equal((await call("PUT", "/api/save", { token: p.token, body: { saved_at: 1, save: [1] } })).status, 400);
  assert.equal((await call("PUT", "/api/save", { token: p.token, body: { save: SAVE } })).status, 400);
  const huge = { saved_at: 5, save: { blob: "x".repeat(1_100_000) } };
  assert.equal((await call("PUT", "/api/save", { token: p.token, body: huge })).status, 413);
  assert.equal((await call("PUT", "/api/save", { body: { saved_at: 1, save: SAVE } })).status, 401);
});

test("create an account, then log in from a new browser and get the save back", async () => {
  const p = await newPlayer("Ada");
  await call("PUT", "/api/save", { token: p.token, body: { saved_at: 3000, save: SAVE } });
  assert.equal((await call("GET", "/api/account", { token: p.token })).data.username, null);

  const made = await call("POST", "/api/account", { token: p.token, body: { username: "Ada_99", password: "correct horse" } });
  assert.equal(made.status, 201);
  assert.equal((await call("GET", "/api/account", { token: p.token })).data.username, "Ada_99");

  // A different browser: no token, just the username (any case) and password.
  const login = await call("POST", "/api/login", { body: { username: "ada_99", password: "correct horse" } });
  assert.equal(login.status, 200);
  assert.equal(login.data.id, p.id);
  assert.equal(login.data.name, "Ada");
  assert.notEqual(login.data.token, p.token);
  const save = await call("GET", "/api/save", { token: login.data.token });
  assert.deepEqual(save.data.save, SAVE);

  // Both browsers stay logged in, and the newest save wins.
  await call("PUT", "/api/save", { token: login.data.token, body: { saved_at: 4000, save: { ...SAVE, day: 8 } } });
  assert.equal((await call("GET", "/api/save", { token: p.token })).data.save.day, 8);
});

test("account rules: valid names and passwords, unique usernames, one account per player", async () => {
  const a = await newPlayer("A");
  const b = await newPlayer("B");
  assert.equal((await call("POST", "/api/account", { token: a.token, body: { username: "no spaces", password: "longenough" } })).status, 400);
  assert.equal((await call("POST", "/api/account", { token: a.token, body: { username: "ok_name", password: "short" } })).status, 400);
  assert.equal((await call("POST", "/api/account", { token: a.token, body: { username: "Wolf", password: "longenough" } })).status, 201);
  const taken = await call("POST", "/api/account", { token: b.token, body: { username: "wolf", password: "longenough" } });
  assert.equal(taken.status, 409);
  assert.equal(taken.data.error, "username_taken");
  const twice = await call("POST", "/api/account", { token: a.token, body: { username: "Other", password: "longenough" } });
  assert.equal(twice.data.error, "already_has_account");
});

test("wrong passwords are refused and rate-limited", async () => {
  const p = await newPlayer();
  await call("POST", "/api/account", { token: p.token, body: { username: "Ada", password: "right password" } });
  const wrong = await call("POST", "/api/login", { body: { username: "Ada", password: "wrong password" } });
  assert.equal(wrong.status, 401);
  assert.equal(wrong.data.error, "wrong_login");
  assert.equal((await call("POST", "/api/login", { body: { username: "nobody", password: "whatever1" } })).status, 401);
  for (let i = 0; i < 9; i++) await call("POST", "/api/login", { body: { username: "Ada", password: "nope nope" } });
  const locked = await call("POST", "/api/login", { body: { username: "Ada", password: "right password" } });
  assert.equal(locked.status, 429);
  // The lock lifts after 15 minutes.
  const later = await call("POST", "/api/login", { body: { username: "Ada", password: "right password" }, now: NOW + 16 * 60 * 1000 });
  assert.equal(later.status, 200);
});

test("passwords are not stored in plain text", async () => {
  const p = await newPlayer();
  await call("POST", "/api/account", { token: p.token, body: { username: "Ada", password: "my secret pw" } });
  const rows = (await db.execute("SELECT * FROM accounts")).rows;
  assert.equal(rows.length, 1);
  assert.ok(!JSON.stringify(rows).includes("my secret pw"));
  assert.match(String(rows[0].password_hash), /^[0-9a-f]{64}$/);
});
