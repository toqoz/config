{
  lib,
  fetchurl,
  fetchzip,
  stdenvNoCC,
}:

let
  version = "0.18.1";
  inherit (stdenvNoCC.hostPlatform) system;
  sources = {
    aarch64-darwin = {
      platform = "darwin_arm64";
      sha256 = "209ad49fcd6a8a863681291f2689edc0fe29ed77dfe7c19d1c8e39153f2316d1";
    };
    x86_64-darwin = {
      platform = "darwin_x86_64";
      sha256 = "eafdfb7c0e3ae57fb41ea63f3e3b535e5443b456575e8c836d4d63e2bb0b7f9a";
    };
    aarch64-linux = {
      platform = "linux_arm64";
      sha256 = "ed491074272223651577549ccf0eabba4c63d0dca82370a9fd1a94e71b141fa4";
    };
    x86_64-linux = {
      platform = "linux_x86_64";
      sha256 = "fa4ab93fcf16a4dc0f8ac01a32c53bd7e302ba1061d0246b70ca7656baacd995";
    };
  };
  source = sources.${system} or (throw "ketch: unsupported platform ${system}");
  upstream = fetchzip {
    url = "https://github.com/1broseidon/ketch/archive/refs/tags/v${version}.tar.gz";
    hash = "sha256-vXSYQJBZ0Eypy3S0qvJUEEk9SZnnIWmQ5DU3TGyuwfk=";
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
