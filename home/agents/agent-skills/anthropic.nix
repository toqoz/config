{ pkgs, lib, anthropic-skills, ... }:

let
  # Real soffice CLI binary. On darwin, nixpkgs' `libreoffice-bin` ships the
  # LibreOffice.app bundle and a $out/bin/soffice *wrapper* that just runs
  # `open -na` — async and headless-unfriendly. Point at the real binary
  # inside the app bundle so subprocess calls behave synchronously.
  sofficePath =
    if pkgs.stdenv.isDarwin then
      "${pkgs.libreoffice-bin}/Applications/LibreOffice.app/Contents/MacOS/soffice"
    else
      "${pkgs.libreoffice}/bin/soffice";

  # Wrap a single binary from a (possibly multi-binary) package so it
  # surfaces as a standalone single-bin derivation. agent-skills-nix then
  # symlinks it into the bundle as `./<name>` at the skill root.
  mkBinWrapper = pkg: name: pkgs.writeShellScriptBin name ''
    exec "${pkg}/bin/${name}" "$@"
  '';

  sofficeWrapper = pkgs.writeShellScriptBin "soffice" ''
    exec "${sofficePath}" "$@"
  '';

  # Python interpreter with `deps` packages, and the `bin/` of every
  # derivation in `extraBinDirs` prepended to PATH so library calls that
  # shell out (pytesseract, pdf2image, soffice.py, …) resolve without
  # relying on the user profile.
  mkPython = { deps, extraBinDirs ? [ ] }: pkgs.writeShellScriptBin "python" ''
    export PATH=${lib.concatStringsSep ":" (map (d: "${d}/bin") extraBinDirs)}:$PATH
    exec ${pkgs.python3.withPackages deps}/bin/python3 "$@"
  '';

  # Background for the cwd note + injection helper below.
  #
  # The wrappers we add via `packages` (e.g. `python`, `pdftoppm`) are
  # symlinked into each skill's bundle as `./python`, `./pdftoppm`, and so
  # on. `mkCmdTransform` rewrites the skill's SKILL.md accordingly so the
  # agent invokes the bundled wrapper instead of whatever happens to be on
  # $PATH. That keeps the agent from silently falling back to an
  # unrelated system Python or missing binary.
  #
  # The catch: `./foo` is resolved against the shell's current working
  # directory. Upstream Anthropic skills never told the agent to cd into
  # the skill directory before running commands — they assumed tools were
  # globally available. With the rewrite applied, running a command from
  # anywhere other than the skill root breaks.
  #
  # So we inject a short blockquote at the top of SKILL.md (just under the
  # YAML frontmatter) explicitly telling the agent to run `./` commands
  # from the skill's own directory. It has to go *after* the frontmatter
  # because Claude Code's SKILL.md parser requires the `---` fence to be
  # the very first thing in the file.
  cwdNote = ''
    > **Run `./` commands from this skill's directory.** The wrappers
    > (`./python`, `./pdftoppm`, …) live next to this `SKILL.md` and are
    > resolved relative to your current working directory. `cd` into this
    > skill's directory before running any command shown below.
  '';

  # Split on the frontmatter's closing `\n---\n` and reassemble with the
  # note sitting between frontmatter and body.
  injectAfterFrontmatter = note: content:
    let
      parts = lib.splitString "\n---\n" content;
    in
    if builtins.length parts >= 2 then
      (builtins.head parts)
      + "\n---\n\n"
      + note
      + "\n"
      + lib.concatStringsSep "\n---\n" (builtins.tail parts)
    else
      note + "\n\n" + content;

  # Rewrite SKILL.md so the named commands run from the skill root via `./`,
  # matching the wrappers installed into the bundle by `packages`.
  mkCmdTransform = cmds: { original, dependencies }:
    let
      variants = c: [
        "`${c} "
        "\n${c} "
        "  ${c} "
        "| ${c} "
        "&& ${c} "
      ];
      replacedVariants = c: [
        "`./${c} "
        "\n./${c} "
        "  ./${c} "
        "| ./${c} "
        "&& ./${c} "
      ];
      patterns = lib.concatMap variants cmds;
      replacements = lib.concatMap replacedVariants cmds;
      rewritten = builtins.replaceStrings patterns replacements original;
      patched = injectAfterFrontmatter cwdNote rewritten;
    in
    ''
      ${patched}

      ${dependencies}
    '';

  # Some skills (pdf, …) spread invocations across multiple *.md files
  # (forms.md, reference.md). The bundle's `transform` hook only sees
  # SKILL.md, so for those we patch the whole tree in a derivation and
  # point an auxiliary source at it — the bundle symlinks the patched
  # files as-is.
  patchSkillScript = pkgs.writeText "patch-skill.py" ''
    import pathlib
    import sys

    root = pathlib.Path(sys.argv[1])
    cmds = sys.argv[2:]
    prefixes = ['`', '\n', '  ', '| ', '&& ']

    NOTE = (
        "> **Run `./` commands from this skill's directory.** The wrappers\n"
        "> (`./python`, `./pdftoppm`, …) live next to this `SKILL.md` and are\n"
        "> resolved relative to your current working directory. `cd` into this\n"
        "> skill's directory before running any command shown below.\n"
    )

    def inject_after_frontmatter(text, note):
        head, sep, rest = text.partition('\n---\n')
        if sep and head.startswith('---\n'):
            return head + '\n---\n\n' + note + '\n' + rest.lstrip('\n')
        return note + '\n\n' + text

    for md in root.rglob('*.md'):
        text = md.read_text()
        for c in cmds:
            for p in prefixes:
                text = text.replace(p + c + ' ', p + './' + c + ' ')
        if md.name == 'SKILL.md':
            text = inject_after_frontmatter(text, NOTE)
        md.write_text(text)
  '';

  mkPatchedSkill = { name, cmds }:
    let
      cmdsShell = lib.concatStringsSep " " (map lib.escapeShellArg cmds);
    in
    pkgs.runCommand "agent-skill-${name}-patched"
      { preferLocalBuild = true; nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        mkdir -p "$out/${name}"
        cp -rL ${anthropic-skills}/skills/${name}/. "$out/${name}/"
        chmod -R u+w "$out/${name}"
        python3 ${patchSkillScript} "$out/${name}" ${cmdsShell}
      '';

  pdftoppmWrapper = mkBinWrapper pkgs.poppler-utils "pdftoppm";

  xlsxPython = mkPython {
    deps = ps: with ps; [ pandas openpyxl defusedxml lxml ];
    extraBinDirs = [ sofficeWrapper ];
  };

  pptxPython = mkPython {
    deps = ps: with ps; [ python-pptx pillow defusedxml lxml markitdown ];
    extraBinDirs = [ sofficeWrapper ];
  };

  docxPython = mkPython {
    deps = ps: with ps; [ python-docx defusedxml lxml ];
    extraBinDirs = [ sofficeWrapper ];
  };

  pdfPython = mkPython {
    deps = ps: with ps; [ pypdf pdfplumber pdf2image pytesseract pypdfium2 reportlab pillow ];
    extraBinDirs = [ pkgs.poppler-utils pkgs.tesseract ];
  };

  pdfCmds = [ "python" "pdftotext" "pdftoppm" "pdfimages" "qpdf" "tesseract" ];
  pdfPatched = mkPatchedSkill { name = "pdf"; cmds = pdfCmds; };

  # Anthropic skills enabled unmodified.
  #
  # Omitted:
  #   - xlsx, pptx, docx, pdf — handled by `skills.explicit.*` below with
  #     nix-pinned Python + external binaries.
  #   - slack-gif-creator, web-artifacts-builder, mcp-builder — disabled
  #     (heavy runtime deps / not useful without a per-project setup).
  #
  # Upstream additions need to be named here explicitly.
  anthropicPassthroughSkills = [
    "doc-coauthoring"
    "frontend-design"
    "internal-comms"
    "skill-creator"
  ];
in
{
  programs.agent-skills.skills.enable = anthropicPassthroughSkills;

  programs.agent-skills.sources = {
    anthropic = {
      path = anthropic-skills;
      subdir = "skills";
    };
    # Auxiliary source for skills whose non-SKILL.md files also need
    # rewriting. `idPrefix` keeps the patched skill's catalog id
    # (`patched/pdf`) from colliding with anthropic's own `pdf` entry
    # during discovery; the bundle still surfaces it as plain `pdf` via
    # `skills.explicit.pdf` below.
    anthropic-patched = {
      path = pdfPatched;
      idPrefix = "patched";
    };
  };

  programs.agent-skills.skills.explicit = {
    xlsx = {
      from = "anthropic";
      path = "xlsx";
      packages = [ xlsxPython ];
      transform = mkCmdTransform [ "python" ];
    };
    pptx = {
      from = "anthropic";
      path = "pptx";
      packages = [ pptxPython pdftoppmWrapper ];
      transform = mkCmdTransform [ "python" "pdftoppm" ];
    };
    docx = {
      from = "anthropic";
      path = "docx";
      packages = [ docxPython pdftoppmWrapper ];
      transform = mkCmdTransform [ "python" "pdftoppm" ];
    };
    # No transform: the patched source already rewrote SKILL.md +
    # forms.md + reference.md.
    pdf = {
      from = "anthropic-patched";
      path = "pdf";
      packages = [
        pdfPython
        (mkBinWrapper pkgs.poppler-utils "pdftotext")
        (mkBinWrapper pkgs.poppler-utils "pdftoppm")
        (mkBinWrapper pkgs.poppler-utils "pdfimages")
        (mkBinWrapper pkgs.qpdf "qpdf")
        (mkBinWrapper pkgs.tesseract "tesseract")
      ];
    };
  };
}
