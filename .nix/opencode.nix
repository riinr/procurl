{ pkgs, ... }:
{
  files.json."/opencode.json" = {
    # Opencode configuration — writes to opencode.json
    opencode."$schema" = "https://opencode.ai/config.json";
    opencode.skills.paths = [ "./nim-skills" ];
    opencode.lsp = {
      nim = {
        command = [ "nimlangserver" ];
        extensions = [ ".nim" ];
      };
    };
    opencode.mcp = {
      hydradb = {
        enabled = true;
        type = "local";
        command = [ "npx" "-y" "@hydradb/mcp@latest" ];
        environment = {
          # {env:...} is opencode's placeholder for environment variable lookup
          HYDRA_DB_API_KEY = "{env:HYDRA_DB_API_KEY}";
          HYDRA_DB_TENANT_ID = "hugosenari";
        };
      };
    };
  };
}
