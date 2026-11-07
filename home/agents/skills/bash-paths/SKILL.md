---
name: bash-paths
description: Quote literal file paths containing shell-special characters when constructing shell commands, especially Next.js []/() routes, Remix $ parameters, spaces, or apostrophes. Applies to shell command strings, not native file-tool path arguments.
user-invocable: false
---

# Literal Shell Paths

- Preserve the exact path; prevent variable expansion, globbing, and command parsing.
- Single-quote literal paths. If the path contains an apostrophe, escape it by closing the quote, adding `\'`, and reopening it.
- For a path already stored in a variable, use `"$path"`.
- Pass native file-tool paths directly, without shell quoting or escapes.

```bash
cat 'app/(main)/users/[userId]/page.tsx'
cat 'app/routes/users.$userId.tsx'
cat 'docs/O'\''Reilly $draft [v1].md'
```
