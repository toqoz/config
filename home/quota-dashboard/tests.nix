{ pkgs }:
{
  collector = pkgs.runCommand "quota-dashboard-collector-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    cp ${./collector.py} collector.py
    cp ${./test_collector.py} test_collector.py
    python3 -m unittest -v test_collector.py
    touch "$out"
  '';
}
