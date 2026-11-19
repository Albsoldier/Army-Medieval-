// Cloudflare Worker entry point for the Last Light island server.
// Secrets (set with `npx wrangler secret put NAME`):
//   TURSO_DATABASE_URL  libsql://<db>-<org>.turso.io
//   TURSO_AUTH_TOKEN    from `turso db tokens create <db>`
// Variable (wrangler.toml):
//   ALLOWED_ORIGIN      where the game is hosted, or * (the API uses bearer tokens, not cookies)

import { createClient } from "@libsql/client/web";
import { handle } from "./app.js";

export default {
  async fetch(request, env) {
    const db = createClient({ url: env.TURSO_DATABASE_URL, authToken: env.TURSO_AUTH_TOKEN });
    return handle(request, env, db);
  },
};
