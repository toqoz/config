{
  stdenv,
  lib,
  fetchurl,
}:

let
  version = "0.23.25";

  # Pre-built release artifacts published at https://ntn.dev/releases/.
  # No source repository is published (Beta), so we consume the
  # vendor-signed binaries directly. Refresh `version` and each `sha256`
  # together when bumping — the checksums are served alongside the
  # tarballs as `<archive>.tar.gz.sha256`.
  sources = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      sha256 = "53196c36f98fbf94f56837dd5997872b51baf5226824c3cbd8cf7dc1f966ea5c";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      sha256 = "eca69bc0bf6f4a26c8aff8608d779aeba9233d77801d962d15e9d8fc45c1b5bb";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      sha256 = "8379954cdb82a3c60866a18923da5f43a3358a6c8c698c085cc2905e7255a927";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      sha256 = "99faf81af403553b66d0f06a466ba6ba6b0e2708fb6b8f1eac2cf7ad1d5db47f";
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
