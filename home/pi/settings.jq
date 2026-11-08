(. // {}) as $settings | $settings + {
  defaultProvider: "ollama",
  defaultModel: "deepseek-v4.1-flash:cloud",
  defaultThinkingLevel: "low",
  extensions: (($settings.extensions // []) | map(select(. != "-builtin:mcp"))),
  packages: (($settings.packages // []) | map(select(
    (if type == "string" then . else (.source // "") end)
    | test("^npm:pi-mcp-adapter(@|$)") | not
  )))
}
