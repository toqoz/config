{ config, lib, pkgs, ... }:
let
  tomlFormat = pkgs.formats.toml { };
  agentPolicy = import ../policy { inherit lib; };

  managedSettings =
    {
      model = "gpt-5.4";

      features.multi_agent = true;

      notice.model_migrations."gpt-5.1-codex-mini" = "gpt-5.4";
    }
    // lib.optionalAttrs config.programs.mcp.enable {
      mcp_servers = lib.mapAttrs (
        _name: server:
        (lib.removeAttrs server [
          "disabled"
          "headers"
        ])
        // (lib.optionalAttrs (server ? headers && !(server ? http_headers)) {
          http_headers = server.headers;
        })
        // {
          enabled = !(server.disabled or false);
        }
      ) config.programs.mcp.servers;
    };

  managedConfig = tomlFormat.generate "codex-config-managed" managedSettings;
in
{
  programs.codex = {
    enable = true;
    package = null;

    context = ../AGENTS.md;

    rules = {
      default = agentPolicy.codexRulesText;
    };
  };

  home.file.".codex/config.managed.toml".source = managedConfig;

  home.activation.mergeCodexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${lib.makeBinPath [ pkgs.python3 ]}:$PATH"

    config_dir="$HOME/.codex"
    managed_config="$config_dir/config.managed.toml"
    live_config="$config_dir/config.toml"

    mkdir -p "$config_dir"
    umask 077
    tmp_config="$(mktemp "$config_dir/config.toml.XXXXXX")"
    trap 'rm -f "$tmp_config"' EXIT

    python3 - "$managed_config" "$live_config" "$tmp_config" <<'PY'
    import json
    import os
    import re
    import sys
    import tomllib

    managed_path, live_path, output_path = sys.argv[1:4]

    def load_projects(path: str) -> dict:
        if not os.path.exists(path):
            return {}
        try:
            with open(path, "rb") as f:
                data = tomllib.load(f)
        except Exception:
            return {}
        projects = data.get("projects", {})
        return projects if isinstance(projects, dict) else {}

    _BARE_KEY_RE = re.compile(r"^[A-Za-z0-9_-]+$")

    def format_key(key: str) -> str:
        return key if _BARE_KEY_RE.match(key) else json.dumps(key)

    def format_value(value):
        if isinstance(value, bool):
            return "true" if value else "false"
        if isinstance(value, int):
            return str(value)
        if isinstance(value, float):
            return repr(value)
        if isinstance(value, str):
            return json.dumps(value)
        if isinstance(value, list):
            return "[" + ", ".join(format_value(item) for item in value) + "]"
        raise TypeError(f"unsupported TOML value: {value!r}")

    def emit_table(lines: list[str], path: list[str], table: dict) -> None:
        scalar_items = []
        child_tables = []
        for key, value in table.items():
            if isinstance(value, dict):
                child_tables.append((key, value))
            else:
                scalar_items.append((key, value))

        if path:
            if lines and lines[-1] != "":
                lines.append("")
            lines.append("[" + ".".join(format_key(part) for part in path) + "]")

        for key, value in scalar_items:
            lines.append(f"{format_key(key)} = {format_value(value)}")

        for key, value in child_tables:
            emit_table(lines, [*path, key], value)

    with open(managed_path, "r", encoding="utf-8") as f:
        managed_text = f.read().rstrip()

    lines = [managed_text] if managed_text else []
    projects = load_projects(live_path)
    if projects:
        emit_table(lines, ["projects"], projects)

    rendered = "\n".join(lines).rstrip() + "\n"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(rendered)
    PY

    mv "$tmp_config" "$live_config"
    chmod 600 "$live_config"
    trap - EXIT
  '';
}
