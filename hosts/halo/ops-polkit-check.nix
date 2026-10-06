# Evaluates the generated polkit rule against stub subjects/actions: the live
# polkitd refuses detail-bearing pkcheck from non-root callers.
{
  pkgs,
  lib,
}: let
  polkit = import ./ops-polkit.nix {inherit lib;};
  harness = pkgs.writeText "halo-ops-polkit-check.js" ''
    const rules = [];
    const polkit = {
      addRule: (f) => rules.push(f),
      Result: { YES: "yes" },
    };
    eval(${builtins.toJSON "(function(){ ${polkit.rule} })()"});
    if (rules.length !== 1) throw new Error("expected 1 rule, got " + rules.length);

    const allowed = ${builtins.toJSON polkit.allowed};
    const run = (user, id, unit, verb) =>
      rules[0](
        { id, lookup: (k) => ({ unit, verb })[k] },
        { user },
      );
    const ACT = "org.freedesktop.systemd1.manage-units";
    let failed = 0;
    const expect = (want, user, id, unit, verb) => {
      const got = run(user, id, unit, verb);
      if (got !== want) {
        console.error("FAIL " + [user, id, unit, verb] + ": want " + want + ", got " + got);
        failed++;
      }
    };

    for (const user of ["noams", "hermes-assistant"])
      for (const [unit, verbs] of Object.entries(allowed))
        for (const verb of verbs) expect("yes", user, ACT, unit, verb);

    expect(undefined, "noams", ACT, "sshd.service", "restart");
    expect(undefined, "noams", ACT, "lemond.service", "start");
    expect(undefined, "noams", ACT, "display-manager.service", "restart");
    expect(undefined, "noams", ACT, "lemond.service.foo", "start");
    expect(undefined, "noams", ACT, "halo-rebuild@x.service", "start");
    expect(undefined, "noams", ACT, "halo-rebuild.servicex", "start");
    expect(undefined, "noams", ACT, "constructor", "start");
    expect(undefined, "noams", "org.freedesktop.login1.reboot", "halo-reboot.service", "start");
    expect(undefined, "hermes-assistant", ACT, "sshd.service", "restart");
    expect(undefined, "hermes-assistant", ACT, "hermes-agent.service", "restart");
    expect(undefined, "hermes-assistant", "org.freedesktop.login1.reboot", "halo-reboot.service", "start");
    for (const [unit, verbs] of Object.entries(allowed))
      for (const verb of verbs) expect(undefined, "hermes", ACT, unit, verb);

    if (failed) process.exit(1);
  '';
in
  pkgs.runCommand "halo-ops-polkit" {nativeBuildInputs = [pkgs.nodejs];} ''
    node ${harness} || { echo "halo-ops polkit rule check failed" >&2; exit 1; }
    touch $out
  ''
