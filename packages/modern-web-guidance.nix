{ lib, stdenvNoCC, fetchurl, nodejs, makeWrapper }:

stdenvNoCC.mkDerivation rec {
  pname = "modern-web-guidance";
  version = "0.0.169";

  src = fetchurl {
    url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
    hash = "sha512-grDxBu7SflBSyKMYlgKtp0eE276LQAUIr/4qVKgnZouvlA0VLpszigYpmFfl+URqYxqjLr0u4Er3KiHpIAs6RQ==";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/${pname}" "$out/bin"
    cp -R . "$out/lib/${pname}/"
    makeWrapper ${lib.getExe nodejs} "$out/bin/modern-web-guidance" \
      --add-flags "$out/lib/${pname}/skills/modern-web-guidance/modern-web.mjs"

    runHook postInstall
  '';

  meta = {
    description = "Search tool for modern web development best practices";
    homepage = "https://github.com/GoogleChrome/modern-web-guidance";
    license = lib.licenses.asl20;
    mainProgram = "modern-web-guidance";
  };
}
