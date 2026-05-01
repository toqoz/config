{
  description = "Home Manager configuration of toqoz";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agent-skills = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    anthropic-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };
    vercel-agent-browser = {
      url = "github:vercel-labs/agent-browser";
      flake = false;
    };
    sence = {
      url = "github:toqoz/sence";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gws = {
      url = "github:googleworkspace/cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-darwin,
      llm-agents,
      agent-skills,
      anthropic-skills,
      vercel-agent-browser,
      sence,
      gws,
      android-nixpkgs,
      ...
    }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs { inherit system; };
      mkDarwinCommand =
        {
          command,
          useSudo ? false,
        }:
        pkgs.writeShellApplication {
          name = "darwin-${command}";
          runtimeInputs = [
            pkgs.git
            nix-darwin.packages.${system}.default
          ];
          text = ''
            set -euo pipefail

            repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
            ${if useSudo then "exec sudo darwin-rebuild ${command} --flake \"$repo_root#remilis\" \"$@\"" else "exec darwin-rebuild ${command} --flake \"$repo_root#remilis\" \"$@\""}
          '';
        };
    in
    {
      packages.${system} = {
        build = mkDarwinCommand { command = "build"; };
        switch = mkDarwinCommand {
          command = "switch";
          useSudo = true;
        };
      };

      apps.${system} = {
        build = {
          type = "app";
          program = "${self.packages.${system}.build}/bin/darwin-build";
        };
        switch = {
          type = "app";
          program = "${self.packages.${system}.switch}/bin/darwin-switch";
        };
      };

      # Auto-discover per-module tests at `home/<mod>/tests.nix`. Each such
      # file is a function `{ pkgs }: { <test-name> = drv; ... }` whose keys
      # are then prefixed with `<mod>-` to land at
      # `checks.<system>.<mod>-<test-name>`. Adding tests for a new module
      # is a matter of dropping a `tests.nix` next to it; no edit here.
      checks.${system} =
        let
          inherit (nixpkgs) lib;
          modules = builtins.readDir ./home;
          candidates = lib.mapAttrsToList
            (name: _: { mod = name; path = ./home + "/${name}/tests.nix"; })
            modules;
          present = builtins.filter ({ path, ... }: builtins.pathExists path) candidates;
        in
        builtins.listToAttrs (lib.concatMap
          ({ mod, path }:
            lib.mapAttrsToList
              (testName: drv: { name = "${mod}-${testName}"; value = drv; })
              (import path { inherit pkgs; })
          )
          present);

      darwinConfigurations."remilis" = nix-darwin.lib.darwinSystem {
        modules = [
          ./darwin/configuration.nix
          home-manager.darwinModules.home-manager
          {
            users.users."toqoz".home = "/Users/toqoz";
            # android-nixpkgs' hmModule references `pkgs.androidSdk`, which is
            # supplied by its overlay. Because `home-manager.useGlobalPkgs` is
            # true, the overlay must live at the nix-darwin `nixpkgs` level.
            nixpkgs.overlays = [
              android-nixpkgs.overlays.default
              # Local workarounds for nixpkgs-unstable / darwin breakage
              # encountered after a `nix flake update`. Two clusters:
              #
              # 1. The `pptx` skill pulls `python3Packages.markitdown`,
              #    whose audio subgraph (pydub, speechrecognition,
              #    openai-whisper, faster-whisper, av) trips a chain of
              #    sandbox-killed test/import phases and a transitive
              #    libcdio-paranoia compile error on darwin. The pptx
              #    skill only ever uses markitdown for PPTX → markdown
              #    conversion, so we strip the audio deps from
              #    markitdown directly — that cuts the failing subtree
              #    off at the root and avoids per-leaf overrides.
              #    `ffmpeg-full → ffmpeg-headless` is kept as a belt
              #    in case any other consumer in the closure pulls
              #    ffmpeg-full (kvazaar / chromaprint / libcdio-paranoia
              #    are not built into the headless variant).
              #
              # 2. The nixpkgs build of zsh-5.9 (aarch64-darwin) hits a
              #    SIGCHLD-delivery race in `getoutput → waitforpid →
              #    signal_suspend → pause` that hangs roughly 1-in-3
              #    `$(...)` / `<(...)` substitutions at startup, making
              #    `zsh -i -c '...'` lock up at random. Apple's stock
              #    `/bin/zsh` (also 5.9) does not exhibit this — measured
              #    0/20 vs 14/20 hangs across identical rcs. Both are
              #    zsh 5.9 but built with different patches/libs, so this
              #    is specific to the nixpkgs derivation, not the zsh
              #    upstream. Until the regression is tracked down, swap
              #    only the binary while keeping the package's
              #    share/zsh/* tree (completions, functions, helpers) so
              #    the rest of the nix-darwin / Home Manager wiring
              #    keeps working unchanged.
              #
              # `python3Packages` is re-aliased explicitly because the
              # top-level alias in nixpkgs is frozen at the original
              # `python3.pkgs` and does NOT track this overlay —
              # consumers that reference `python3Packages.<pkg>` would
              # otherwise silently fall back to the unpatched python.
              (final: prev: {
                ffmpeg-full = prev.ffmpeg-headless;
                zsh = prev.zsh.overrideAttrs (old: {
                  postFixup = (old.postFixup or "") + ''
                    rm -f $out/bin/zsh
                    ln -s /bin/zsh $out/bin/zsh
                  '';
                });
                python3 = prev.python3.override {
                  packageOverrides = _: pyprev: {
                    markitdown = pyprev.markitdown.overridePythonAttrs (old:
                      let
                        excluded = [ "pydub" "speechrecognition" "openai-whisper" "faster-whisper" "av" ];
                        keep = p: !(builtins.elem (p.pname or p.name or "") excluded);
                      in
                      {
                        propagatedBuildInputs = builtins.filter keep (old.propagatedBuildInputs or [ ]);
                        dependencies = builtins.filter keep (old.dependencies or [ ]);
                        doCheck = false;
                      });
                  };
                };
                python3Packages = final.python3.pkgs;
              })
            ];
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.sharedModules = [
              agent-skills.homeManagerModules.default
              android-nixpkgs.hmModule
            ];
            home-manager.extraSpecialArgs = {
              inherit llm-agents;
              inherit anthropic-skills;
              inherit vercel-agent-browser;
              inherit sence;
              inherit gws;
            };
            home-manager.users."toqoz" = ./home/home.nix;
          }
        ];
      };
    };
}
