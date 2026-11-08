{ lib, stdenvNoCC, fetchurl, unzip }:

stdenvNoCC.mkDerivation rec {
  pname = "kanary";
  version = "4.2.1";

  src = fetchurl {
    url = "https://distro.kanary.to/releases/Kanary-${version}.zip";
    hash = "sha256-Kj/YVLqoYB4eQkHnsJ8X2QvRsQIx0yZkgOk6gj1oAEw=";
  };

  nativeBuildInputs = [ unzip ];
  dontUnpack = true;
  # Keep the upstream code signature intact.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    unzip -q "$src" 'Kanary.app/*' -d "$out/Applications"
    runHook postInstall
  '';

  meta = {
    description = "Mac menu bar assistant with local transcription and voice input";
    homepage = "https://kanary.to/";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-darwin" ];
  };
}
