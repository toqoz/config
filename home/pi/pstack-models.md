# pstack model configuration

These role overrides load through the pstack Pi extension. Delete a role line to use the skill default. `inherit-parent` and `auto` use the parent model. Each panel entry starts one agent. The cross-judge pool supplies one judge.

`pi models` maps pstack aliases to Pi provider/model IDs. `default effort: medium` applies unless a role or panel entry has an `@level` suffix. `session hook: on` enables task routing instructions at session start.

pi models: opus=openai-codex/gpt-6.1-sol, fable=opencode-go/glm-5.3, sonnet=opencode-go/kimi-k3, haiku=opencode-go/claude-haiku-5-5

feature, refactoring: sonnet
bug-fix: opus @xhigh
perf-issue: opus @high
hillclimb: opus @high
judgment and prose: opus @high
strongest judgment: opus @xhigh
how explorer: sonnet
how explainer: opus @high
why investigators: sonnet
why synthesizer: opus @high
reflect tooling: sonnet
reflect judgment, divergent, synthesizer: opus @high
arena runners: opus @high, sonnet @high, fable @high
arena cross-judge pool: opus @high, sonnet @high, fable @high
swarm workers: sonnet
architect runners: opus @high, sonnet @high, fable @high
interrogate reviewers: opus @high, sonnet @high, fable @high

default effort: medium
session hook: on
