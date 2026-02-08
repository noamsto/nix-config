# Go Bills - Shared Bills Management Service
{config, ...}: {
  services.go-bills = {
    enable = true;
    port = 8082;
    baseURL = "/bills";
    uploadsDir = "/data/bills";
    database = {
      user = "go_bills";
      name = "go_bills";
      password = "go_bills";
    };
    sessionSecret = "naspi-bills-session-2024";
    geminiApiKeyFile = config.age.secrets.go-bills-gemini-key.path;
  };
}
