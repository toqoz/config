# Patch staging

Capture inspected changes rather than reconstructing file contents by hand.
Store disposable patches under `./.agents/cache/patches/` and regenerate them
from the current index and working tree after each commit.

## Entire paths

For exact paths with no staged changes, after checking every change belongs to
the current commit unit, capture a path-scoped patch mechanically. Use literal
pathspecs for filenames containing Git glob characters:

```bash
mkdir -p ./.agents/cache/patches
git diff --binary --full-index --find-renames -- ':(literal)path/to/file' > ./.agents/cache/patches/selected.patch
```

For a rename, include both the old and new literal paths. Inspect the patch,
including mode changes, then dry-run and apply the same unedited file:

```bash
git apply --cached --check --recount ./.agents/cache/patches/selected.patch
git apply --cached --recount ./.agents/cache/patches/selected.patch
```

Do not use `--include` as an exact-path selector: it interprets patterns.
A captured patch stages the inspected content even if the working file changes
later; inspect remaining differences before reporting what was committed.

## New files

Generate a new-file patch without retyping the content:

```bash
git diff --no-index --binary --full-index -- /dev/null 'path/to/new-file' > ./.agents/cache/patches/new-file.patch
```

Exit status 1 means differences were found; distinguish it from an error.
Inspect the patch and apply it with the same check/apply commands above.
An intent-to-add file already appears in ordinary `git diff`.

## Partial changes and existing staging

Inspect `git diff --staged` and `git diff` separately. Unstaged patches are
relative to the current index; do not overwrite a partial staged selection
with working-tree contents. Preserve scope and ask before repartitioning
existing staging as required by the main skill.

Capture the unstaged diff, retain file headers and select the relevant hunks.
Edit within a hunk only when needed; preserve context and inspect the resulting
staged content for transcription errors. Run `--check --recount` before apply.
If separation cannot be done safely, explain the overlap and ask how to proceed.

After application, inspect `git diff --staged` and run
`git diff --staged --check`. On failure, inspect the actual index and regenerate
the patch rather than retrying blindly. Preserve unrelated changes.
