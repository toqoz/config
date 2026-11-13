{ lib, homeDirectory }:
let
  # Keep the source policy structured in Nix instead of parsing Claude-style
  # strings back into data. Claude and Codex are rendered from the same entries.
  bashPrefix = pattern: {
    kind = "bash-prefix";
    targets = [
      "claude"
      "codex"
    ];
    inherit pattern;
  };

  claudeBashPrefix = pattern: {
    kind = "bash-prefix";
    targets = [ "claude" ];
    inherit pattern;
  };

  codexBashPrefix = pattern: {
    kind = "bash-prefix";
    targets = [ "codex" ];
    inherit pattern;
  };

  # Skills are installed per target, so each agent resolves notify.py under its
  # own skills directory: ~/.claude/skills for Claude Code, ~/.agents/skills for
  # Codex and the shared agent skills.
  grokbotNotify = entry: skillsDir: entry [
    "python3"
    "${homeDirectory}/${skillsDir}/skills/grokbot-notify/scripts/notify.py"
  ];

  claudePathPermission =
    action: path:
    {
      kind = "claude-path-permission";
      targets = [ "claude" ];
      inherit action path;
    };

  claudeMcpPermission = name: {
    kind = "claude-mcp-permission";
    targets = [ "claude" ];
    inherit name;
  };

  renderClaudePermission =
    entry:
    if entry.kind == "bash-prefix" then
      "Bash(${lib.concatStringsSep " " entry.pattern} *)"
    else if entry.kind == "claude-path-permission" then
      "${entry.action}(${entry.path})"
    else if entry.kind == "claude-mcp-permission" then
      entry.name
    else
      throw "Unsupported Claude permission kind: ${entry.kind}";

  renderCodexRule =
    decision: entry:
    if entry.kind != "bash-prefix" then
      throw "Unsupported Codex rule kind: ${entry.kind}"
    else
      "prefix_rule(pattern=[${lib.concatStringsSep ", " (map builtins.toJSON entry.pattern)}], decision=${builtins.toJSON decision})";

  renderClaudePermissions =
    entries: map renderClaudePermission (lib.filter (entry: builtins.elem "claude" entry.targets) entries);

  renderCodexRules =
    decision:
    entries: map (renderCodexRule decision) (lib.filter (entry: builtins.elem "codex" entry.targets) entries);

  sharedPolicy = {
    deny = [
      (bashPrefix [ "sudo" ])

      (claudePathPermission "Read" ".env")
      (claudePathPermission "Edit" ".env")
      (claudePathPermission "Read" "*.env")
      (claudePathPermission "Edit" "*.env")
      (claudePathPermission "Read" "*.vars")
      (claudePathPermission "Edit" "*.vars")
    ];

    allow = [
      # Sending the current thread ID to the Grokbot webhook is pre-authorized
      # (see the Grokbot Notifications section of home/agents/AGENTS.md). Only
      # the skill's own script is allow-listed, not arbitrary python3.
      (grokbotNotify claudeBashPrefix ".claude")
      (grokbotNotify bashPrefix ".agents")

      (claudePathPermission "Read" "~/agents/**")
      (claudePathPermission "Write" "~/agents/**")
      (claudePathPermission "Edit" "~/agents/**")

      (bashPrefix [
        "codex"
        "exec"
        "--sandbox"
        "read-only"
        "--ephemeral"
      ])
      (bashPrefix [
        "gh"
        "repo"
        "view"
        "--json"
        "defaultBranchRef"
        "--jq"
      ])
      (bashPrefix [ "echo" ])
      (bashPrefix [ "find" ])
      (bashPrefix [ "grep" ])
      (bashPrefix [ "head" ])
      (bashPrefix [ "ls" ])
      (bashPrefix [ "mkdir" ])
      (bashPrefix [ "tail" ])
      (bashPrefix [ "git" "add" ])
      (bashPrefix [ "git" "apply" ])
      (bashPrefix [ "git" "blame" ])
      (bashPrefix [ "git" "checkout" ])
      (bashPrefix [ "git" "cherry-pick" ])
      (bashPrefix [ "git" "commit" ])
      (bashPrefix [ "git" "diff" ])
      (bashPrefix [ "git" "fetch" ])
      (bashPrefix [ "git" "log" ])
      (bashPrefix [ "git" "merge" ])
      (bashPrefix [ "git" "mv" ])
      (bashPrefix [ "git" "pull" ])
      (bashPrefix [ "git" "rm" ])
      (bashPrefix [ "git" "show" ])
      (bashPrefix [ "git" "stash" ])
      (bashPrefix [ "git" "status" ])
      (bashPrefix [ "gh" "pr" "checks" ])
      (bashPrefix [ "gh" "pr" "diff" ])
      (bashPrefix [ "gh" "pr" "list" ])
      (bashPrefix [ "gh" "pr" "status" ])
      (bashPrefix [ "gh" "pr" "view" ])
      (bashPrefix [ "gh" "run" "list" ])
      (bashPrefix [ "gh" "run" "status" ])
      (bashPrefix [ "gh" "run" "view" ])
      (bashPrefix [ "gh" "run" "watch" ])
      (bashPrefix [ "gh" "search" ])
      (bashPrefix [ "nix" "build" ])
      (bashPrefix [ "nix" "fmt" ])
      (bashPrefix [ "nix" "log" ])
      (bashPrefix [ "cargo" "tree" ])
      (bashPrefix [ "npm" "list" ])
      (bashPrefix [ "pnpm" "list" ])
      (bashPrefix [ "agent-browser" ])
      (bashPrefix [ "docker" "compose" "ps" ])

      (claudeMcpPermission "mcp__plugin_claude-code-home_Figma__get_code")
      (claudeMcpPermission "mcp__plugin_claude-code-home_Figma__get_code_connect_map")
      (claudeMcpPermission "mcp__plugin_claude-code-home_Figma__get_design_context")
      (claudeMcpPermission "mcp__plugin_claude-code-home_Figma__get_image")
      (claudeMcpPermission "mcp__plugin_claude-code-home_Figma__get_metadata")
      (claudeMcpPermission "mcp__plugin_claude-code-home_Figma__get_screenshot")
      (claudeMcpPermission "mcp__plugin_claude-code-home_Figma__get_variable_defs")
    ];
  };

  codexOnlyAllow = [
    # Keep existing Codex-only affordances that do not belong in Claude
    # permissions.
    (codexBashPrefix [ "sort" ])
    (codexBashPrefix [
      "env"
      "XDG_CACHE_HOME=/tmp/nix-cache"
      "NIX_CONFIG=experimental-features = nix-command flakes"
      "nix"
      "flake"
      "lock"
      "--print-build-logs"
      "--update-input"
      "llm-agents"
      "--override-input"
      "llm-agents"
      "github:numtide/llm-agents.nix?rev=6fd26c9cb50d9549f3791b3d35e4f72f97677103"
    ])
  ];
in
{
  inherit sharedPolicy;

  claudePermissions = {
    allow = renderClaudePermissions sharedPolicy.allow;
    deny = renderClaudePermissions sharedPolicy.deny;
  };

  codexRulesText =
    lib.concatStringsSep "\n" (
      renderCodexRules "allow" sharedPolicy.allow
      ++ renderCodexRules "allow" codexOnlyAllow
      ++ renderCodexRules "forbidden" sharedPolicy.deny
    )
    + "\n";
}
