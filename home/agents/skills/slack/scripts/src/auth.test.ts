/**
 * Unit tests for auth subcommands.
 *
 * Run:  node --experimental-transform-types --no-warnings=ExperimentalWarning \
 *         --test src/auth.test.ts
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { main } from "./auth.ts";
import { UsageError } from "./helpers/cli.ts";

async function captureStdout(fn: () => Promise<void>): Promise<string> {
  const originalLog = console.log;
  const lines: string[] = [];
  console.log = (...args: unknown[]) => {
    lines.push(args.map(String).join(" "));
  };
  try {
    await fn();
  } finally {
    console.log = originalLog;
  }
  return lines.join("\n");
}

async function withAuthConfig<T>(config: unknown, fn: () => Promise<T>): Promise<T> {
  const oldXdgDataHome = process.env.XDG_DATA_HOME;
  const dir = mkdtempSync(join(tmpdir(), "slack-auth-test-"));
  process.env.XDG_DATA_HOME = dir;

  try {
    const configDir = join(dir, "slack-skill");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(join(configDir, "auth.json"), JSON.stringify(config) + "\n");
    return await fn();
  } finally {
    if (oldXdgDataHome === undefined) {
      delete process.env.XDG_DATA_HOME;
    } else {
      process.env.XDG_DATA_HOME = oldXdgDataHome;
    }
    rmSync(dir, { recursive: true, force: true });
  }
}

describe("auth", () => {
  it("lists configured workspaces, verifies auth.test, and does not expose stored secrets", async () => {
    const originalFetch = globalThis.fetch;
    const urls: string[] = [];
    globalThis.fetch = async (input: string | URL | Request) => {
      const url = String(input instanceof Request ? input.url : input);
      urls.push(url);
      const isTeam2 = url.includes("team2.slack.com");
      return new Response(JSON.stringify({
        ok: true,
        url: isTeam2 ? "https://team2.slack.com" : "https://team1.slack.com",
        team: isTeam2 ? "Team 2" : "Team 1",
        user: isTeam2 ? "U222" : "U111",
      }));
    };

    try {
      const stdout = await withAuthConfig(
        {
          default: "https://team1.slack.com",
          workspaces: {
            "https://team2.slack.com": {
              token: "xoxc-secret",
              cookie: "xoxd-secret",
              type: "browser",
              workspaceUrl: "https://team2.slack.com",
              teamName: "Configured Team 2",
            },
            "https://team1.slack.com": {
              token: "xoxb-secret",
              type: "api",
              workspaceUrl: "https://team1.slack.com",
              teamName: "Configured Team 1",
            },
          },
        },
        () => captureStdout(() => main(["list"])),
      );
      const data = JSON.parse(stdout);

      assert.equal(data.ok, true);
      assert.equal(data.default, "https://team1.slack.com");
      assert.deepEqual(urls.sort(), [
        "https://slack.com/api/auth.test",
        "https://team2.slack.com/api/auth.test",
      ]);
      assert.deepEqual(data.workspaces, [
        {
          workspace: "https://team1.slack.com",
          team: "Team 1",
          token_type: "api",
          default: true,
          status: "ok",
          user: "U111",
          api_url: "https://team1.slack.com",
        },
        {
          workspace: "https://team2.slack.com",
          team: "Team 2",
          token_type: "browser",
          default: false,
          status: "ok",
          user: "U222",
          api_url: "https://team2.slack.com",
        },
      ]);
      assert.equal(stdout.includes("xoxb-secret"), false);
      assert.equal(stdout.includes("xoxc-secret"), false);
      assert.equal(stdout.includes("xoxd-secret"), false);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("marks expired credentials as an auth error", async () => {
    const originalFetch = globalThis.fetch;
    const oldExitCode = process.exitCode;
    globalThis.fetch = async () => new Response(JSON.stringify({ ok: false, error: "invalid_auth" }));
    process.exitCode = undefined;

    try {
      const stdout = await withAuthConfig(
        {
          default: "https://team1.slack.com",
          workspaces: {
            "https://team1.slack.com": {
              token: "xoxb-expired",
              type: "api",
              workspaceUrl: "https://team1.slack.com",
              teamName: "Team 1",
            },
          },
        },
        () => captureStdout(() => main(["list"])),
      );
      const data = JSON.parse(stdout);

      assert.equal(data.ok, false);
      assert.equal(process.exitCode, 1);
      assert.deepEqual(data.workspaces, [
        {
          workspace: "https://team1.slack.com",
          team: "Team 1",
          token_type: "api",
          default: true,
          status: "error",
          error: "Slack API error: invalid_auth",
        },
      ]);
    } finally {
      globalThis.fetch = originalFetch;
      process.exitCode = oldExitCode;
    }
  });

  it("rejects unknown subcommands instead of importing desktop credentials", async () => {
    await assert.rejects(
      () => main(["status"]),
      (err: unknown) => err instanceof UsageError && err.message.includes("Unknown auth subcommand: status"),
    );
  });
});
