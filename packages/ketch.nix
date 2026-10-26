{
  lib,
  fetchurl,
  fetchzip,
  stdenvNoCC,
}:

let
  version = "0.20.0";
  inherit (stdenvNoCC.hostPlatform) system;
  sources = {
    aarch64-darwin = {
      platform = "darwin_arm64";
      sha256 = "fb51e6e17c157a2dc91aa6ea8d19e498c07550599747d989f81aebb6fa2143c1";
    };
    x86_64-darwin = {
      platform = "darwin_x86_64";
      sha256 = "34580ceacc93569c269072d7f9b3896faca954727d50f7fb518c3e90671c3243";
    };
    aarch64-linux = {
      platform = "linux_arm64";
      sha256 = "3d56bcacee4da209f19f1728802830083df1d7c6c71a70a03930bce8b5b22602";
    };
    x86_64-linux = {
      platform = "linux_x86_64";
      sha256 = "791720b097f86d7b369f3353e3ea8337ece3f59f8e1275d459b5694ab27b6565";
    };
  };
  source = sources.${system} or (throw "ketch: unsupported platform ${system}");
  upstream = fetchzip {
    url = "https://github.com/1broseidon/ketch/archive/refs/tags/v${version}.tar.gz";
    hash = "sha256-+XtyOg+JClB5hzdYJIAm1IK3ZXp1A4sjAh2jSuExzOw=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "ketch";
  inherit version;

  src = fetchurl {
    url = "https://github.com/1broseidon/ketch/releases/download/v${version}/ketch_${version}_${source.platform}.tar.gz";
    inherit (source) sha256;
  };
  sourceRoot = ".";
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 ketch "$out/bin/ketch"
    mkdir -p "$out/share/ketch/skills"
    cp -R ${upstream}/skills/ketch "$out/share/ketch/skills/ketch"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Stateless CLI for web search, code search, library docs, and scraping";
    homepage = "https://github.com/1broseidon/ketch";
    license = licenses.mit;
    mainProgram = "ketch";
    platforms = builtins.attrNames sources;
  };
}
