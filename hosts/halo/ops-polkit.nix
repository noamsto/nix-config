{lib}: rec {
  # A future bot uid is one more entry here.
  users = ["noams"];

  allowed = {
    "halo-rebuild.service" = ["start"];
    "halo-update-prepare.service" = ["start"];
    "halo-update-push.service" = ["start"];
    "halo-reboot.service" = ["start"];
    "lemond.service" = ["restart"];
    "ds4-server.service" = ["restart"];
    "display-manager.service" = ["start" "stop"];
  };

  # Own-property lookup so prototype keys such as "constructor" never match.
  rule = lib.concatStringsSep "\n" [
    "(function () {"
    "var users = ${builtins.toJSON users};"
    "var allowed = ${builtins.toJSON allowed};"
    ''
      polkit.addRule(function (action, subject) {
        if (action.id != "org.freedesktop.systemd1.manage-units") return;
        if (users.indexOf(subject.user) < 0) return;
        var unit = action.lookup("unit");
        var verbs = allowed.hasOwnProperty(unit) ? allowed[unit] : null;
        if (verbs && verbs.indexOf(action.lookup("verb")) >= 0) return polkit.Result.YES;
      });
    ''
    "})();"
  ];
}
