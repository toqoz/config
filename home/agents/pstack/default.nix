{
  pkgs,
  ...
}:
let
  # pstack-claude 0.9.102 (the multi-harness port of cursor/plugins pstack).
  # Pinned like home/pi/default.nix does for the Pi install; the two revisions
  # are kept equal by t/agent-pstack.test.mts.
  rev = "356c6e0f978df729eb16f227d795f34d221c5aad";
  hash = "sha256-PxD5vgXMTtwgxGP3wFyiSO8TcXh0xTJaym2+VpVf4LE=";

  source = pkgs.fetchgit {
    url = "https://github.com/michael-denyer/pstack-claude";
    inherit rev hash;
  };

  # Curated catalogue. DSH pays for every description in the system prompt, so
  # this is a subset rather than all 65 skills: the router, the principles it
  # references (poteto-mode reads `../principle-*/SKILL.md` as siblings),
  # prose/style skills that fire on their own, and the workflows in use.
  # Add a name here to expose another skill.
  enabled = [
    "poteto-mode"
    "setup-pstack"

    "benchmark-checklist"

    "principle-attack-the-premise"
    "principle-boundary-discipline"
    "principle-build-the-lever"
    "principle-encode-lessons-in-structure"
    "principle-exhaust-the-design-space"
    "principle-experience-first"
    "principle-explain-the-number"
    "principle-fix-root-causes"
    "principle-foundational-thinking"
    "principle-guard-the-context-window"
    "principle-laziness-protocol"
    "principle-make-operations-idempotent"
    "principle-migrate-callers-then-delete-legacy-apis"
    "principle-minimize-reader-load"
    "principle-model-the-domain"
    "principle-never-block-on-the-human"
    "principle-outcome-oriented-execution"
    "principle-prove-it-works"
    "principle-redesign-from-first-principles"
    "principle-separate-before-serializing-shared-state"
    "principle-sequence-verifiable-units"
    "principle-subtract-before-you-add"
    "principle-test-behavior-not-implementation"
    "principle-type-system-discipline"

    "unslop"
    "deslop"
    "correct"
    "sharpen"
    "no-comments"
    "technical-writing"

    "tdd"
    "how"
    "why"
    "recall"

    "arena"
    "interrogate"
    "architect"
    "swarm"
    "reflect"

    "get-pr-comments"
    "fix-ci"
    "fix-merge-conflicts"
  ];
in
{
  programs.agent-skills.sources.pstack = {
    path = source;
    subdir = "plugins/pstack/skills";
  };

  programs.agent-skills.skills.enable = enabled;

  # The skill texts point at files outside the skills tree: the plugin's agent
  # definitions (`plugins/pstack/agents/*.md`) and `models.json`. Expose the
  # whole pinned checkout so those paths resolve without a mutable clone.
  home.file.".agents/pstack-src".source = source;

  # User-global instruction read by DSH on every session. Keep it to the
  # routing rules; the tool/alias mapping lives in the pstack-dsh skill so it
  # costs tokens only when a pstack skill is actually used.
  home.file.".agents/AGENTS.md".text = ''
    - Before using a pstack skill, read the `pstack-dsh` skill for the DSH tool
      and model mapping.
    - Use `poteto-mode` when asked for it, and consider it for difficult tasks
      (multiple files, design decisions, ambiguity, high risk). Do not load it
      for routine work.
    - Run `unslop` after writing prose, and `deslop` after leaving a diff.
  '';
}
