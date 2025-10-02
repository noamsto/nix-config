{
  lib,
  fetchFromGitHub,
  buildNpmPackage,
}:
buildNpmPackage rec {
  pname = "tavily-mcp";
  version = "0.2.10";

  src = fetchFromGitHub {
    owner = "tavily-ai";
    repo = "tavily-mcp";
    rev = "fea64be37d3a9589547d8c66af4fb8505fd2b265"; # Latest commit (no tags available)
    hash = "sha256-gqyPeJWRvsLrkDbQYFv3mW1+IVqtWmgrcVsdDWG9JVk=";
  };

  npmDepsHash = "sha256-QsWzfIa3t0V6fH2wlyafB2B6WH7gr5nV6PS1Q4+gXNY=";

  # The package builds TypeScript to JavaScript
  # Output is in build/index.js which is executable
  dontNpmBuild = false;

  meta = {
    description = "Production-ready MCP server for web search using Tavily API";
    homepage = "https://github.com/tavily-ai/tavily-mcp";
    license = lib.licenses.mit;
    maintainers = [];
    mainProgram = "tavily-mcp";
  };
}
