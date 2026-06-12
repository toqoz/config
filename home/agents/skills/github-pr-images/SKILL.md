---
name: github-pr-images
description: Upload local images (screenshots, diagrams, GIFs) to a GitHub PR's prerelease storage and return the raw asset URLs. Use whenever the user wants to host images for a PR body from the CLI, refresh images on an existing PR, or clean up image storage after merge. The caller is responsible for deciding how to embed the URLs (plain Markdown, `<details>`, tables, alt text wording, etc.).
---

# github-pr-images

Upload images to a PR-scoped prerelease and return `name<TAB>url` pairs.
GitHub has no official CLI API for PR-body attachments; a prerelease is
the supported substitute that keeps private-repo captures inside the
repo's visibility boundary.

Embedding is the caller's job. This skill never emits Markdown and never
edits a PR body — it only uploads and reports URLs.

## Prerequisites

- `gh` authenticated against the target repo.
- The target PR already exists.

## Inputs

- `PR_NUMBER` — the PR to attach to. Ask the user if missing.
- `REPO` — `OWNER/NAME`. Resolve once with
  `gh repo view --json nameWithOwner -q .nameWithOwner`, or accept an
  explicit value from the user when running outside a clone.
- Image paths — resolve any globs *before* calling `gh`.

## Release target branch

Use a dedicated orphan branch named `pr-images` as the target for image
release tags. This keeps `pr-<PR_NUMBER>-images` tags off mainline commits
and PR commits; many image releases can safely target the same anchor commit.

If the branch is missing, create it as an orphan branch before creating the
release. Use GitHub's Git Data API so this also works when running outside a
local clone:

```bash
ensure_image_release_target_branch() {
  branch="$1"

  if gh api "repos/${REPO}/branches/${branch}" -R "$REPO" >/dev/null 2>&1; then
    return 0
  fi

  empty_tree_sha="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
  commit_sha=$(gh api "repos/${REPO}/git/commits" -R "$REPO" \
    --method POST \
    --field message="Release asset anchor branch" \
    --field tree="$empty_tree_sha" \
    --jq .sha)

  if gh api "repos/${REPO}/git/refs" -R "$REPO" \
    --method POST \
    --field ref="refs/heads/${branch}" \
    --field sha="$commit_sha" >/dev/null
  then
    return 0
  fi

  # Another uploader may have created it concurrently. Treat that as success.
  gh api "repos/${REPO}/branches/${branch}" -R "$REPO" >/dev/null
}
```

## Preflight

Fail early, not mid-upload:

```bash
IMAGE_RELEASE_TARGET_BRANCH="${IMAGE_RELEASE_TARGET_BRANCH:-pr-images}"

gh pr view "$PR_NUMBER" -R "$REPO" --json number >/dev/null   # PR exists
ensure_image_release_target_branch "$IMAGE_RELEASE_TARGET_BRANCH"
for f in "$@"; do [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }; done
# Unique basenames — the URL lookup below keys off basename.
basenames=$(for f in "$@"; do basename "$f"; done | sort)
[ "$(echo "$basenames" | uniq -d)" = "" ] || { echo "basename collision" >&2; exit 1; }
```

## Upload

The release is tagged `pr-<PR_NUMBER>-images`. Branch on existence so
genuine failures surface instead of being swallowed by a `||` fallback:

```bash
IMAGE_RELEASE_TARGET_BRANCH="${IMAGE_RELEASE_TARGET_BRANCH:-pr-images}"
TAG="pr-${PR_NUMBER}-images"

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$@" --clobber -R "$REPO"
else
  gh release create "$TAG" "$@" \
    --title "PR #${PR_NUMBER} screenshots" \
    --notes "Image assets for PR #${PR_NUMBER}. Auto-generated." \
    --prerelease \
    --target "$IMAGE_RELEASE_TARGET_BRANCH" \
    -R "$REPO"
fi
```

`--target` anchors new release tags to the dedicated image branch instead
of whatever commit happens to be the default branch HEAD. `--prerelease`
keeps these out of the normal release list. `--clobber` overwrites existing
assets of the same name on re-upload.

## Return URLs

Emit one `<basename><TAB><url>` line per input file, in input order, to
stdout. The caller decides how to render them — inline image, link text,
`<details>` block, table, etc. Filenames often make poor alt text, so
producing Markdown here would force a bad default.

Fetch the asset list once and resolve names locally — per-file API calls
waste chatter and can hit transient consistency gaps right after upload.
Pass filenames via `--arg` so names containing quotes or backslashes do
not break the `jq` filter.

```bash
assets=$(gh api "repos/${REPO}/releases/tags/${TAG}" -R "$REPO" \
  --jq '[.assets[] | {name, url: .browser_download_url}]')

for f in "$@"; do
  name=$(basename "$f")
  url=$(printf '%s' "$assets" | jq -r --arg n "$name" \
    '.[] | select(.name == $n) | .url')
  printf '%s\t%s\n' "$name" "$url"
done
```

The emitted URL is accessible to anyone with read access to the repo.

## Cleanup after merge

```bash
gh release delete "pr-${PR_NUMBER}-images" --cleanup-tag --yes -R "$REPO"
```
