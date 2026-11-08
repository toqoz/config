---
name: notion-cli
description: Use ntn for Notion operations, including reading or editing pages, querying databases, uploading files, and managing workers.
---

# Notion CLI

- Use `ntn` for Notion operations.
- Check `ntn <command> --help` before running commands. For API endpoints, use `ntn api ls`, `--docs`, and `--spec` to discover current syntax and schemas instead of guessing.
- Prefer an existing `NOTION_API_TOKEN`. Check whether it is set without printing its value, and do not request `ntn login` when a token is already available.
- Prefer Markdown for page content and comments. Use structured rich text only when Markdown cannot represent the required content.
