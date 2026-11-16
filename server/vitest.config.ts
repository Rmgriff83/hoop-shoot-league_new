import path from "node:path";
import { defineConfig } from "vitest/config";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-pool-workers";

export default defineConfig(async () => {
  const migrations = await readD1Migrations(path.join(import.meta.dirname, "migrations"));
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.toml" },
        // PLATFORM_TEST_VERIFIER lives here only: the `test` proof verifier never exists in a deploy.
        // REVENUECAT_WEBHOOK_AUTH and the PLAY_GAMES_* pair are Worker secrets in production; the suite's values are these.
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            PLATFORM_TEST_VERIFIER: "on",
            REVENUECAT_WEBHOOK_AUTH: "test-auth",
            PLAY_GAMES_CLIENT_ID: "test-web-client.apps.googleusercontent.com",
            PLAY_GAMES_CLIENT_SECRET: "test-web-secret",
          },
        },
      }),
    ],
    test: { setupFiles: ["./test/apply_migrations.ts"] },
  };
});
