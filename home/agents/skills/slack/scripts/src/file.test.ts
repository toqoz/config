/**
 * Unit tests for parseFilePermalink.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { parseFilePermalink } from "./file.ts";

describe("parseFilePermalink", () => {
  it("parses a standard Slack file permalink", () => {
    const result = parseFilePermalink(
      "https://myteam.slack.com/files/U01234567/F0ABCDE/screenshot.png",
    );
    assert.deepEqual(result, { fileId: "F0ABCDE" });
  });

  it("parses a permalink without a trailing filename", () => {
    const result = parseFilePermalink(
      "https://myteam.slack.com/files/U01234567/F0ABCDE",
    );
    assert.deepEqual(result, { fileId: "F0ABCDE" });
  });

  it("parses a permalink with a query string", () => {
    const result = parseFilePermalink(
      "https://myteam.slack.com/files/U01234567/F0ABCDE/x.png?download_url=https%3A%2F%2Ffiles.slack.com%2F...",
    );
    assert.deepEqual(result, { fileId: "F0ABCDE" });
  });

  it("returns null for non-file Slack URLs", () => {
    assert.equal(
      parseFilePermalink(
        "https://myteam.slack.com/archives/C01234567/p1700000000123456",
      ),
      null,
    );
  });

  it("returns null for non-Slack URLs", () => {
    assert.equal(parseFilePermalink("https://example.com/files/foo/bar"), null);
  });

  it("returns null for empty string", () => {
    assert.equal(parseFilePermalink(""), null);
  });

  it("handles enterprise grid subdomains", () => {
    const result = parseFilePermalink(
      "https://company.enterprise.slack.com/files/W99999999/F9XYZ/data.csv",
    );
    assert.deepEqual(result, { fileId: "F9XYZ" });
  });
});
