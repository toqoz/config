{ pkgs }:
let
  python = pkgs.python3;
in
{
  collector = pkgs.runCommand "quota-dashboard-collector-tests" { nativeBuildInputs = [ python ]; } ''
    cp ${./collector.py} collector.py
    cp ${./test_collector.py} test_collector.py
    python3 -m unittest -v test_collector.py
    touch "$out"
  '';

  api = pkgs.runCommand "quota-dashboard-api-tests" { nativeBuildInputs = [ python ]; } ''
    cp ${./api.py} api.py
    cp ${./test_api.py} test_api.py
    python3 -m unittest -v test_api.py
    touch "$out"
  '';
}
