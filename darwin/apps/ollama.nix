{ ... }:
{
  homebrew.brews = [
    {
      name = "ollama";
      # Replace the CLI symlink previously installed by ollama-app.
      args = [ "overwrite" ];
      link = "overwrite";
      restart_service = "changed";
    }
  ];
}
