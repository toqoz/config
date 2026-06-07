/**
 * Auth management: import credentials from Slack Desktop or manual tokens.
 *
 * Subcommands:
 *   list                 List configured workspaces
 *   import-desktop       Extract xoxc+xoxd from Slack Desktop (macOS)
 *   import-desktop --set-default
 *   import-token --token xoxb-...
 *   import-token --token xoxc-... --cookie xoxd-...
 */

import { execFileSync } from "node:child_process";
import { statSync, mkdtempSync, rmSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, basename } from "node:path";
import { loadAuth, saveAuth, slackGet, parseArgs, fatal, output, usage, findKeysContaining } from "./helpers/index.ts";

interface DesktopTeam {
  url: string;
  name?: string;
  token: string;
}

const AUTH_USAGE = `Usage: slack-cli auth <subcommand> [args]

Subcommands:
  list                              List configured workspaces
  import-desktop [--set-default]    Import credentials from Slack Desktop
  import-token --token ...          Import a bot/user token
  import-token --token ... --cookie xoxd-...

Common options:
  --workspace <url-or-substring>    Select workspace where supported`;

export async function main(args: string[]) {
  const { flags, positional } = parseArgs(args);
  const cmd = positional[0];

  switch (cmd) {
    case "list":
      await listAuth();
      return;
    case "import-desktop":
      await importDesktop(flags["set-default"] === true);
      return;
    case "import-token":
      await importManualToken(
        (flags["token"] as string) ?? fatal("--token is required"),
        flags["cookie"] as string | undefined,
      );
      return;
    case undefined:
      if (flags["token"]) {
        await importManualToken(
          flags["token"] as string,
          flags["cookie"] as string | undefined,
        );
        return;
      }
      usage(AUTH_USAGE);
    default:
      usage(`Unknown auth subcommand: ${cmd}\n\n${AUTH_USAGE}`);
  }
}

async function listAuth(): Promise<void> {
  const config = loadAuth();
  const workspaces = await Promise.all(
    Object.entries(config.workspaces)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(async ([workspaceUrl, ws]) => {
        const base = {
          workspace: workspaceUrl,
          team: ws.teamName,
          token_type: ws.type,
          default: workspaceUrl === config.default,
        };

        try {
          const authInfo = await slackGet<{ url: string; team: string; user: string }>(
            "auth.test",
            {},
            ws,
          );
          return {
            ...base,
            status: "ok",
            team: authInfo.team ?? ws.teamName,
            user: authInfo.user,
            api_url: authInfo.url,
          };
        } catch (e) {
          return {
            ...base,
            status: "error",
            error: e instanceof Error ? e.message : String(e),
          };
        }
      }),
  );
  const ok = workspaces.every((ws) => ws.status === "ok");

  output({
    ok,
    default: config.default,
    workspaces,
  });
  if (!ok) process.exitCode = 1;
}

async function importDesktop(setDefault: boolean): Promise<void> {
  const home = process.env.HOME ?? fatal("$HOME not set");
  const slackDir = `${home}/Library/Application Support/Slack`;

  console.error("Extracting Slack Desktop credentials…");
  const [teams, xoxd] = await Promise.all([
    extractTeams(slackDir),
    extractXoxd(slackDir),
  ]);

  if (teams.length === 0) {
    fatal(
      "Could not find xoxc tokens in Slack Desktop storage.\n" +
      "Is Slack Desktop installed and logged in?\n" +
      "Alternative: slack-cli auth import-token --token xoxb-...",
    );
  }
  if (!xoxd) {
    fatal(
      "Could not decrypt xoxd cookie from Slack Desktop.\n" +
      "Ensure you grant Keychain access when prompted.\n" +
      "Alternative: slack-cli auth import-token --token xoxc-... --cookie xoxd-...",
    );
  }

  console.error(`Found ${teams.length} workspace(s). Verifying…`);
  await importAllTeams(teams, xoxd, setDefault);
}

// ── Team extraction (LevelDB reader) ─────────────────────────────

function dirExists(path: string): boolean {
  try { return statSync(path).isDirectory(); } catch { return false; }
}

function fileExists(path: string): boolean {
  try { return statSync(path).isFile(); } catch { return false; }
}

async function extractTeams(slackDir: string): Promise<DesktopTeam[]> {
  const leveldbDir = `${slackDir}/Local Storage/leveldb`;
  if (!dirExists(leveldbDir)) return [];

  let snap: string | null = null;
  try {
    snap = mkdtempSync(join(tmpdir(), "slack-skill-ldb-"));
    try {
      execFileSync("cp", ["-cR", leveldbDir, snap], { stdio: "ignore" });
    } catch {
      execFileSync("cp", ["-R", leveldbDir, snap], { stdio: "ignore" });
    }
    const snapDir = join(snap, basename(leveldbDir));

    try { unlinkSync(join(snapDir, "LOCK")); } catch { /* ignore */ }

    // findKeysContaining returns deduplicated entries (newest version
    // per user key, tombstones removed) so we just need to find the
    // best matching localConfig key.
    const needle = new TextEncoder().encode("localConfig_v");
    const entries = findKeysContaining(snapDir, needle);

    const v2 = new TextEncoder().encode("localConfig_v2");
    const v3 = new TextEncoder().encode("localConfig_v3");

    // Prefer v3 over v2 (newer schema). If the preferred version
    // parses but yields no teams, fall back to the other version.
    const candidates: Array<{ version: number; value: Uint8Array }> = [];
    for (const entry of entries) {
      if (uint8Includes(entry.key, v3)) {
        candidates.push({ version: 3, value: entry.value });
      } else if (uint8Includes(entry.key, v2)) {
        candidates.push({ version: 2, value: entry.value });
      }
    }
    // Sort descending by version so v3 is tried first.
    candidates.sort((a, b) => b.version - a.version);

    for (const c of candidates) {
      const teams = parseLocalConfigTeams(c.value);
      if (teams.length > 0) return teams;
    }
    return [];
  } catch (e) {
    console.error("Warning: LevelDB read failed:", e instanceof Error ? e.message : String(e));
    return [];
  } finally {
    if (snap) {
      try { rmSync(snap, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  }
}

function uint8Includes(haystack: Uint8Array, needle: Uint8Array): boolean {
  outer: for (let i = 0; i <= haystack.length - needle.length; i++) {
    for (let j = 0; j < needle.length; j++) {
      if (haystack[i + j] !== needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

function parseLocalConfigTeams(raw: Uint8Array): DesktopTeam[] {
  const first = raw[0];
  const data = (first === 0x00 || first === 0x01 || first === 0x02) ? raw.subarray(1) : raw;

  let nullCount = 0;
  for (const b of data) if (b === 0) nullCount++;
  const isUtf16 = nullCount > data.length / 4;
  const encodings: string[] = isUtf16 ? ["utf-16le", "utf-8"] : ["utf-8", "utf-16le"];

  for (const enc of encodings) {
    try {
      const text = new TextDecoder(enc).decode(data);
      const cfg = tryParseJson(text);
      if (!cfg || typeof cfg !== "object") continue;
      const teamsVal = (cfg as Record<string, unknown>)["teams"];
      if (!teamsVal || typeof teamsVal !== "object") continue;

      const result: DesktopTeam[] = [];
      for (const team of Object.values(teamsVal as Record<string, unknown>)) {
        if (!team || typeof team !== "object") continue;
        const t = team as Record<string, unknown>;
        const url = typeof t["url"] === "string" ? t["url"] : null;
        const token = typeof t["token"] === "string" ? t["token"] : null;
        const name = typeof t["name"] === "string" ? t["name"] : undefined;
        if (url && token && token.startsWith("xoxc-")) {
          result.push({ url, name, token });
        }
      }
      if (result.length > 0) return result;
    } catch {
      continue;
    }
  }
  return [];
}

function tryParseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start !== -1 && end > start) {
      try { return JSON.parse(text.slice(start, end + 1)); } catch { /* fall through */ }
    }
    return null;
  }
}

// ── xoxd extraction (Keychain + SQLite + Web Crypto AES-CBC) ─────

async function extractXoxd(slackDir: string): Promise<string | null> {
  // Read encrypted cookie from SQLite first (no password prompt)
  const cookiesCandidates = [
    `${slackDir}/Network/Cookies`,
    `${slackDir}/Cookies`,
  ];
  let cookiesDb: string | null = null;
  for (const p of cookiesCandidates) {
    if (fileExists(p)) { cookiesDb = p; break; }
  }
  if (!cookiesDb) return null;

  let hexValue: string;
  try {
    hexValue = execFileSync(
      "sqlite3",
      [
        cookiesDb,
        "SELECT hex(encrypted_value) FROM cookies " +
        "WHERE host_key LIKE '%.slack.com' AND name='d' " +
        "ORDER BY length(encrypted_value) DESC LIMIT 1",
      ],
      { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] },
    ).trim();
  } catch {
    return null;
  }
  if (!hexValue) return null;

  const encryptedBytes = hexToBytes(hexValue);
  const prefix = new TextDecoder().decode(encryptedBytes.slice(0, 3));
  if (prefix !== "v10" && prefix !== "v11") {
    console.error(`Warning: unknown cookie format '${prefix}'.`);
    return null;
  }
  const ciphertext = encryptedBytes.slice(3);
  const iv = new Uint8Array(16).fill(0x20);

  // Try each Keychain entry one at a time: read password → try decrypt → stop on success.
  // This minimizes password prompts (typically 1).
  const keychainAttempts: string[][] = [
    ["-s", "Slack Safe Storage", "-a", "Slack Key", "-w"],
    ["-s", "Slack Safe Storage", "-a", "Slack App Store Key", "-w"],
    ["-s", "Slack Safe Storage", "-w"],
    ["-s", "Chrome Safe Storage", "-w"],
  ];
  const tried = new Set<string>();

  for (const args of keychainAttempts) {
    let password: string;
    try {
      password = execFileSync(
        "security",
        ["find-generic-password", ...args],
        { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] },
      ).trim();
    } catch {
      continue; // not found → next
    }
    if (!password || tried.has(password)) continue;
    tried.add(password);

    const result = await tryDecrypt(password, ciphertext, iv);
    if (result) return result;
  }

  if (tried.size === 0) {
    console.error("Warning: 'Slack Safe Storage' not found in Keychain.");
  } else {
    console.error("Warning: AES decryption succeeded but xoxd- not found in output.");
  }
  return null;
}

async function tryDecrypt(
  password: string,
  ciphertext: Uint8Array,
  iv: Uint8Array,
): Promise<string | null> {
  try {
    const keyMaterial = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(password),
      "PBKDF2",
      false,
      ["deriveKey"],
    );
    const aesKey = await crypto.subtle.deriveKey(
      {
        name: "PBKDF2",
        salt: new TextEncoder().encode("saltysalt"),
        iterations: 1003,
        hash: "SHA-1",
      },
      keyMaterial,
      { name: "AES-CBC", length: 128 },
      false,
      ["decrypt"],
    );
    const decrypted = await crypto.subtle.decrypt({ name: "AES-CBC", iv }, aesKey, ciphertext);
    const text = new TextDecoder().decode(decrypted);
    const match = text.match(/xoxd-[A-Za-z0-9%/+_=.-]+/);
    if (match) {
      try { return decodeURIComponent(match[0]!); } catch { return match[0]!; }
    }
  } catch {
    // wrong key
  }
  return null;
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16);
  }
  return bytes;
}

// ── Import all teams ─────────────────────────────────────────────

async function importAllTeams(
  teams: DesktopTeam[],
  cookie: string,
  setDefault: boolean,
): Promise<void> {
  const config = loadAuth();
  const imported: Array<{ workspace: string; team: string; user: string }> = [];
  const failed: string[] = [];

  for (const t of teams) {
    try {
      const teamUrl = t.url.replace(/\/$/, "");
      const authInfo = await slackGet<{ url: string; team: string; user: string }>(
        "auth.test",
        {},
        { token: t.token, cookie, type: "browser", workspaceUrl: teamUrl },
      );
      const workspaceUrl = (authInfo.url ?? "").replace(/\/$/, "");
      if (!workspaceUrl) {
        failed.push(`${t.name ?? t.url}: no URL returned`);
        continue;
      }
      config.workspaces[workspaceUrl] = {
        token: t.token,
        cookie,
        type: "browser",
        workspaceUrl,
        teamName: authInfo.team,
      };
      if (!config.default || (setDefault && imported.length === 0)) {
        config.default = workspaceUrl;
      }
      imported.push({ workspace: workspaceUrl, team: authInfo.team, user: authInfo.user });
      console.error(`  ✓ ${authInfo.team} (${workspaceUrl})`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      failed.push(`${t.name ?? t.url}: ${msg}`);
      console.error(`  ✗ ${t.name ?? t.url}: ${msg}`);
    }
  }

  if (imported.length === 0) {
    fatal("All workspace tokens failed auth.test. Tokens may be expired.");
  }

  saveAuth(config);

  output({
    ok: true,
    imported: imported.length,
    failed: failed.length,
    workspaces: imported,
    ...(failed.length > 0 ? { errors: failed } : {}),
  });
}

// ── Manual token import ──────────────────────────────────────────

async function importManualToken(
  token: string,
  cookie?: string,
): Promise<void> {
  const type = token.startsWith("xoxc-") ? "browser" : "api";
  if (type === "browser" && !cookie) {
    fatal("Browser token (xoxc) requires --cookie xoxd-...");
  }

  console.error("Verifying token with auth.test…");
  const authInfo = await slackGet<{ url: string; team: string; user: string }>(
    "auth.test",
    {},
    { token, cookie, type, workspaceUrl: "" },
  ).catch((e: Error) => fatal(`auth.test failed: ${e.message}`));

  const workspaceUrl = (authInfo.url ?? "").replace(/\/$/, "");
  const config = loadAuth();
  config.workspaces[workspaceUrl] = {
    token,
    ...(cookie ? { cookie } : {}),
    type,
    workspaceUrl,
    teamName: authInfo.team,
  };
  if (!config.default) config.default = workspaceUrl;
  saveAuth(config);

  output({
    ok: true,
    workspace: workspaceUrl,
    team: authInfo.team,
    user: authInfo.user,
    token_type: type,
  });
}
