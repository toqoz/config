{ ... }:
{
  programs.mcp = {
    enable = true;
    servers = {
      Figma_0 = {
        type = "http";
        url = "https://mcp.figma.com/mcp";
      };
      Figma_1 = {
        type = "http";
        url = "https://mcp.figma.com/mcp?profile=1";
      };
    };
  };
}
