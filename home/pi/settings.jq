(. // {}) as $settings | $settings + {
  defaultProvider: "openai-codex",
  defaultModel: "gpt-6.1-sol",
  defaultThinkingLevel: "medium",
  extensions: (($settings.extensions // []) | if index("-builtin:mcp") then . else . + ["-builtin:mcp"] end),
  packages: (($settings.packages // []) | map(select(
    (if type == "string" then . else (.source // "") end)
    | test("^(git:(https://)?github[.]com/michael-denyer/pstack-claude([.]git)?([@#]|$)|npm:pi-(intercom|subagents)(@|$))")
    | not
  )))
}
