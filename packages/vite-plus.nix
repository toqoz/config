{
  lib,
  fetchurl,
  stdenv,
  runtimeShell,
}:
let
  version = "1.4.0";
  inherit (stdenv.hostPlatform) system;
  # The `vp` binary is a Rust dispatcher: most subcommands invoke a Node.js
  # entrypoint at `../node_modules/vite-plus/dist/bin.js` relative to the
  # binary's own location. The npm-distributed CLI package contains only the
  # dispatcher; the Node.js backend is fetched separately by `vp upgrade`,
  # which populates $VP_HOME (default ~/.vite-plus) with the versioned
  # node_modules tree.
  #
  # We therefore ship the dispatcher at $out/libexec/vp and expose a wrapper
  # at $out/bin/vp that bootstraps $VP_HOME on first use (or when the pinned
  # version differs) via `vp upgrade`, then execs the real binary.
  sources = {
    "aarch64-darwin" = {
      suffix = "darwin-arm64";
      hash = "sha256-h8OmqE6TVswjuyHwbGUJ3/M892WTS/9mO6RAQCqO4rU=";
    };
  };
  src = sources.${system} or (throw "Unsupported system: ${system}");
in
stdenv.mkDerivation {
  inherit version;
  pname = "vite-plus";

  src = fetchurl {
    url = "https://registry.npmjs.org/@voidzero-dev/vite-plus-cli-${src.suffix}/-/vite-plus-cli-${src.suffix}-${version}.tgz";
    inherit (src) hash;
  };

  sourceRoot = "package";

  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 vp $out/libexec/vp
    mkdir -p $out/bin
    cat > $out/bin/vp <<EOF
    #!${runtimeShell}
    set -e
    export VP_NO_UPDATE_CHECK=1
    : "\''${VP_HOME:=\$HOME/.vite-plus}"
    pinned="${version}"
    current=\$(readlink "\$VP_HOME/current" 2>/dev/null || true)
    if [ "\$current" != "\$pinned" ] || [ ! -x "\$VP_HOME/current/bin/vp" ]; then
      "$out/libexec/vp" upgrade "\$pinned" --force >&2
    fi
    exec "\$VP_HOME/current/bin/vp" "\$@"
    EOF
    chmod +x $out/bin/vp
    runHook postInstall
  '';

  meta = with lib; {
    description = "The Unified Toolchain for the Web";
    homepage = "https://viteplus.dev";
    license = licenses.mit;
    mainProgram = "vp";
    platforms = builtins.attrNames sources;
  };
}
