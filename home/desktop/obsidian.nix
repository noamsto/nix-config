_: {
  programs.obsidian = {
    enable = true;

    defaultSettings = {
      app = {
        vimMode = true;
      };
      corePlugins = [
        "file-explorer"
        "global-search"
        "switcher"
        "graph"
        "backlink"
        "canvas"
        "outgoing-link"
        "tag-pane"
        "page-preview"
        "daily-notes"
        "templates"
        "note-composer"
        "command-palette"
        "slash-command"
        "editor-status"
        "bookmarks"
        "outline"
        "word-count"
        "file-recovery"
        "sync"
        "bases"
        "properties"
      ];
    };

    vaults = {
      "vaults/personal" = {};
      "vaults/work" = {};
    };
  };
}
