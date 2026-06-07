// Types, Keychain access, and auth config persistence.

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fatal } from "./cli.ts";

// ── Types ────────────────────────────────────────────────────────

export interface WorkspaceAuth {
  token: string;
  cookie?: string;
  type: "browser" | "api";
  workspaceUrl: string;
  teamName?: string;
}

export interface AuthConfig {
  default?: string;
  workspaces: Record<string, WorkspaceAuth>;
}

// ── Keychain (macOS) ──────────────────────────────────────────────
//
// All secrets are stored as a single JSON blob in one Keychain entry
// (service=slack-skill, account=secrets). This means only 1 password
// prompt per load and 1 per save, regardless of workspace count.

export const KEYCHAIN_SERVICE = "slack-skill";
export const KEYCHAIN_ACCOUNT = "secrets";
export const KEYCHAIN_PLACEHOLDER = "__KEYCHAIN__";

type SecretsBlob = Record<string, string>; // { "xoxd": "...", "xoxc:https://...": "...", ... }

function keychainLoadAll(): SecretsBlob {
  try {
    const raw = execFileSync(
      "security",
      ["find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT, "-w"],
      { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] },
    ).trim();
    return raw ? JSON.parse(raw) as SecretsBlob : {};
  } catch {
    return {};
  }
}

function keychainSaveAll(blob: SecretsBlob): boolean {
  try {
    execFileSync(
      "security",
      [
        "add-generic-password",
        "-s", KEYCHAIN_SERVICE,
        "-a", KEYCHAIN_ACCOUNT,
        "-w", JSON.stringify(blob),
        "-U",
      ],
      { stdio: "ignore" },
    );
    return true;
  } catch {
    return false;
  }
}

// ── Auth config ──────────────────────────────────────────────────

export function authConfigPath(): string {
  const home = process.env.HOME ?? "";
  const xdgData = process.env.XDG_DATA_HOME ?? `${home}/.local/share`;
  return `${xdgData}/slack-skill/auth.json`;
}

export function loadAuth(opts: { hydrateSecrets?: boolean } = {}): AuthConfig {
  let config: AuthConfig;
  try {
    const text = readFileSync(authConfigPath(), "utf-8");
    config = JSON.parse(text) as AuthConfig;
  } catch {
    return { workspaces: {} };
  }

  if (opts.hydrateSecrets === false) return config;

  // Check if any workspace needs hydration
  const needsHydration = Object.values(config.workspaces).some(
    (ws) => ws.token === KEYCHAIN_PLACEHOLDER || ws.cookie === KEYCHAIN_PLACEHOLDER,
  );
  if (!needsHydration) return config;

  // Single Keychain read for all secrets
  const secrets = keychainLoadAll();

  for (const [url, ws] of Object.entries(config.workspaces)) {
    if (ws.token === KEYCHAIN_PLACEHOLDER) {
      const key = ws.type === "browser" ? `xoxc:${url}` : `token:${url}`;
      const token = secrets[key];
      if (token) ws.token = token;
    }
    if (ws.cookie === KEYCHAIN_PLACEHOLDER) {
      const xoxd = secrets["xoxd"];
      if (xoxd) ws.cookie = xoxd;
    }
  }

  return config;
}

export function saveAuth(
  config: AuthConfig,
  opts: { useKeychain?: boolean } = { useKeychain: true },
): void {
  const path = authConfigPath();
  const dir = path.slice(0, path.lastIndexOf("/"));
  mkdirSync(dir, { recursive: true });

  if (opts.useKeychain) {
    const fileConfig: AuthConfig = { ...config, workspaces: {} };
    const secrets: SecretsBlob = {};

    for (const [url, ws] of Object.entries(config.workspaces)) {
      const entry = { ...ws };

      if (ws.type === "browser") {
        if (ws.cookie && ws.cookie !== KEYCHAIN_PLACEHOLDER) {
          secrets["xoxd"] = ws.cookie;
        }
        entry.cookie = KEYCHAIN_PLACEHOLDER;

        if (ws.token && ws.token !== KEYCHAIN_PLACEHOLDER) {
          secrets[`xoxc:${url}`] = ws.token;
        }
        entry.token = KEYCHAIN_PLACEHOLDER;
      } else {
        if (ws.token && ws.token !== KEYCHAIN_PLACEHOLDER) {
          secrets[`token:${url}`] = ws.token;
        }
        entry.token = KEYCHAIN_PLACEHOLDER;
      }

      fileConfig.workspaces[url] = entry;
    }

    // Single Keychain write for all secrets
    if (Object.keys(secrets).length > 0) {
      keychainSaveAll(secrets);
    }

    writeFileSync(path, JSON.stringify(fileConfig, null, 2) + "\n");
  } else {
    writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
  }
}

export function getWorkspaceAuth(
  config: AuthConfig,
  workspace?: string,
): WorkspaceAuth {
  const key = workspace ?? config.default;
  if (!key) {
    const keys = Object.keys(config.workspaces);
    if (keys.length === 1) return config.workspaces[keys[0]!]!;
    if (keys.length === 0) {
      fatal("No workspaces configured. Run: slack-cli auth import-desktop");
    }
    fatal(
      `Multiple workspaces configured; specify one with --workspace.\nAvailable: ${keys.join(", ")}`,
    );
  }
  if (config.workspaces[key]) return config.workspaces[key]!;
  const match = Object.entries(config.workspaces).find(
    ([k]) => k.includes(key) || key.includes(k),
  );
  if (match) return match[1];
  fatal(
    `Workspace not found: ${key}\nAvailable: ${Object.keys(config.workspaces).join(", ")}`,
  );
}
