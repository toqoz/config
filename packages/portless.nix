{
  lib,
  fetchurl,
  nodejs_24,
  makeWrapper,
  stdenv,
}:
let
  version = "0.12.0";
  hash = "sha256-q5yLEzmfyzf7V9I7qFfW6gwx+gHcWfjMTvBH4OZAnak=";
in
stdenv.mkDerivation {
  inherit version;
  pname = "portless";

  src = fetchurl {
    url = "https://registry.npmjs.org/portless/-/portless-${version}.tgz";
    inherit hash;
  };

  nativeBuildInputs = [ makeWrapper ];

  unpackPhase = ''
    mkdir -p $out/lib/node_modules/portless
    tar xzf $src --strip-components=1 -C $out/lib/node_modules/portless
  '';

  installPhase = ''
    mkdir -p $out/bin
    makeWrapper ${nodejs_24}/bin/node $out/bin/portless --add-flags "$out/lib/node_modules/portless/dist/cli.js"
  '';

  meta = with lib; {
    description = "Replace port numbers with stable, named local URLs. For humans and agents.";
    homepage = "https://github.com/vercel-labs/portless";
    license = licenses.asl20;
    mainProgram = "portless";
  };
}
