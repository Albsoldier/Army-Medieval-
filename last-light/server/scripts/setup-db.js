// Creates the Last Light tables in your Turso database. Works on Windows, macOS and Linux.
// PowerShell:
//   $env:TURSO_DATABASE_URL="libsql://..."; $env:TURSO_AUTH_TOKEN="..."; npm run db:setup
import { readFileSync } from "node:fs";
import { createClient } from "@libsql/client";

const url = process.env.TURSO_DATABASE_URL;
if (!url) {
  console.error("Set TURSO_DATABASE_URL (and TURSO_AUTH_TOKEN) first. See last-light/README.md.");
  process.exit(1);
}
const db = createClient({ url, authToken: process.env.TURSO_AUTH_TOKEN });
await db.executeMultiple(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
const rs = await db.execute("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name");
console.log("Tables ready:", rs.rows.map((r) => r.name).join(", "));
