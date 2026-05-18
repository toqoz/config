/**
 * Slack file operations.
 *
 * Subcommands:
 *   download <permalink>   Download a file by its Slack permalink into ./.agents/cache/slack-cli/files/
 *
 * Common options: --workspace <url-or-substring>
 */

import { createWriteStream, mkdirSync, statSync } from "node:fs";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { resolve } from "node:path";
import {
  loadAuth,
  getWorkspaceAuth,
  slackGet,
  parseArgs,
  output,
  fatal,
  usage,
  type WorkspaceAuth,
} from "./helpers/index.ts";

const CACHE_DIR = ".agents/cache/slack-cli/files";

export async function main(args: string[]) {
  const { flags, positional } = parseArgs(args);
  const workspace = flags["workspace"] as string | undefined;
  const config = await loadAuth();
  const auth = getWorkspaceAuth(config, workspace);
  const cmd = positional[0];

  switch (cmd) {
    case "download": case "dl": {
      await cmdDownload(positional, auth);
      break;
    }
    default: usage("Usage: slack-cli file download <permalink>");
  }
}

interface SlackFile {
  id: string;
  name?: string;
  url_private?: string;
  url_private_download?: string;
  mimetype?: string;
  size?: number;
}

export function parseFilePermalink(input: string): { fileId: string } | null {
  try {
    const u = new URL(input);
    const m = u.pathname.match(/^\/files\/[^/]+\/(F[A-Z0-9]+)(?:\/|$)/);
    if (!m) return null;
    return { fileId: m[1]! };
  } catch {
    return null;
  }
}

async function cmdDownload(positional: string[], auth: WorkspaceAuth) {
  const permalink = positional[1];
  if (!permalink) usage("Usage: slack-cli file download <permalink>");

  const parsed = parseFilePermalink(permalink!);
  if (!parsed) fatal(`Not a Slack file permalink: ${permalink}`);

  const info = await slackGet<{ file: SlackFile }>(
    "files.info",
    { file: parsed.fileId },
    auth,
  );
  const file = info.file;
  const downloadUrl = file.url_private_download ?? file.url_private;
  if (!downloadUrl) fatal(`File has no downloadable URL: ${parsed.fileId}`);

  const destDir = resolve(process.cwd(), CACHE_DIR);
  const name = file.name ?? parsed.fileId;
  const destPath = resolve(destDir, `${parsed.fileId}-${name}`);

  const headers: Record<string, string> = {
    "User-Agent": "slack-skill/1.0 Node",
  };
  if (auth.type === "browser") {
    if (auth.cookie) headers["Cookie"] = `d=${encodeURIComponent(auth.cookie)}`;
  } else {
    headers["Authorization"] = `Bearer ${auth.token}`;
  }

  const res = await fetch(downloadUrl, { headers, redirect: "follow" });
  if (!res.ok) fatal(`Download failed: HTTP ${res.status} ${res.statusText}`);
  if (!res.body) fatal("Download failed: empty response body");

  mkdirSync(destDir, { recursive: true });
  await pipeline(Readable.fromWeb(res.body as never), createWriteStream(destPath));

  const stat = statSync(destPath);
  output({
    ok: true,
    file_id: parsed.fileId,
    name: file.name,
    mimetype: file.mimetype,
    size: stat.size,
    expected_size: file.size,
    path: destPath,
  });
}
