(. // {}) as $settings | $settings + {
  defaultProvider: "ollama",
  defaultModel: "deepseek-v4.1-flash:cloud",
  defaultThinkingLevel: "low",
  extensions: (($settings.extensions // []) | if index("-builtin:mcp") then . else . + ["-builtin:mcp"] end),
  packages: ($settings.packages // [])
}
