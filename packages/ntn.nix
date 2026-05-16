{
  stdenv,
  lib,
  fetchurl,
}:

let
  version = "0.13.2";

  # Pre-built release artifacts published at https://ntn.dev/releases/.
  # No source repository is published (Beta), so we consume the
  # vendor-signed binaries directly. Refresh `version` and each `sha256`
  # together when bumping — the checksums are served alongside the
  # tarballs as `<archive>.tar.gz.sha256`.
  sources = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      sha256 = "40ce5ed7490f9371bc52a28918723f5c2010bf7d9b7a7b30273d8b63b30d5054";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      sha256 = "18dd6f6c289d24f6ef609160923d4ca02f66ea46910b45feae44a028096d7254";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      sha256 = "21c6b57dd7e7dbf8bd653191b3b8c0c0142042c24939ebab46048a7b9f22e2e7";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      sha256 = "44bbcf91e113bd33ef5275d1ee45160f4463bddae53beaeb381273f797d349c9";
    };
  };

  selected =
    sources.${stdenv.hostPlatform.system}
      or (throw "ntn: unsupported platform ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "ntn";
  inherit version;

  src = fetchurl {
    url = "https://ntn.dev/releases/v${version}/ntn-${selected.target}.tar.gz";
    inherit (selected) sha256;
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm0755 ntn $out/bin/ntn
    runHook postInstall
  '';

  meta = with lib; {
    description = "Notion CLI";
    homepage = "https://ntn.dev";
    license = licenses.unfree;
    platforms = builtins.attrNames sources;
    mainProgram = "ntn";
  };
}
