{
  buildRubyGem,
  fetchFromGitHub,
  lib,
  ruby,
}:

let
  oj = buildRubyGem rec {
    inherit ruby;
    gemName = "oj";
    version = "3.17.3";
    source.sha256 = "1v87lxi5cdaw3fvdf046fwzrgfbmi2ndkl31clh4zb5p1dxrdqzb";

    meta = with lib; {
      description = "Optimized JSON parser and object serializer for Ruby";
      homepage = "https://github.com/ohler55/oj";
      license = licenses.mit;
      platforms = ruby.meta.platforms;
    };
  };
in
buildRubyGem rec {
  inherit ruby;
  gemName = "jrf";
  version = "0.1.18";

  src = fetchFromGitHub {
    owner = "kazuho";
    repo = "jrf";
    rev = "v${version}";
    hash = "sha256-pui/8o7TfDQuueqn0sx3JZlwQnafsoFbtqKo1xIDfJQ=";
  };

  propagatedBuildInputs = [ oj ];

  meta = with lib; {
    description = "JSON filter with the power and speed of Ruby";
    homepage = "https://github.com/kazuho/jrf";
    license = licenses.mit;
    platforms = ruby.meta.platforms;
    mainProgram = "jrf";
  };
}
