{
  lib,
  fetchurl,
  stdenvNoCC,
  unzip,
}:

let
  version = "1.4.204";
  inherit (stdenvNoCC.hostPlatform) system;
  sources = {
    "aarch64-darwin" = {
      url = "https://github.com/stablyai/orca/releases/download/v${version}/Orca-${version}-arm64-mac.zip";
      hash = "sha256-6jIrgJdC+srheRtQpwunipJBh0j0soRfPnbPL82E1Po=";
    };
  };
  src = sources.${system} or (throw "orca: unsupported platform ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "orca";
  inherit version;

  src = fetchurl {
    inherit (src) url hash;
  };

  nativeBuildInputs = [ unzip ];

  sourceRoot = ".";

  # Keep the signed app bundle byte-for-byte as shipped. The bundled CLI script
  # intentionally uses /usr/bin/env bash and resolves through symlinks back to
  # Orca.app, so no fixup is needed.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    cp -R Orca.app "$out/Applications/Orca.app"
    ln -s "$out/Applications/Orca.app/Contents/Resources/bin/orca" "$out/bin/orca"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Agent Development Environment for shipping software with AI agents";
    homepage = "https://github.com/stablyai/orca";
    license = licenses.mit;
    mainProgram = "orca";
    platforms = builtins.attrNames sources;
  };
}
