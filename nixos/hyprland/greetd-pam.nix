{
  pkgs,
  config,
  lib,
  ...
}: let
  # greetd's auth chain checks a typed password at once; only an empty submit
  # (noctalia sends "", other clients omit the response) waits on the reader.
  # account/password/session stay nixpkgs' login include/substack.
  login = config.security.pam.services.login;
  loginAuth = login.rules.auth;
  pamModule = n: "${config.security.pam.package}/lib/security/${n}.so";

  # Reads the token pam_exec pipes in and never prints it; absolute wc because
  # PAM leaves PATH unset for pam_exec children.
  authtokNonEmpty = pkgs.writeShellScript "pam-authtok-nonempty" ''
    [ "$(${pkgs.coreutils}/bin/wc -c)" -gt 0 ]
  '';

  hasLidCheck = loginAuth ? fprintd-lid-check && loginAuth.fprintd-lid-check.enable;

  fingerprintRules =
    lib.optionalAttrs hasLidCheck {
      fprintd-lid-check = {
        inherit (loginAuth.fprintd-lid-check) control modulePath args;
        order = 11100;
      };
    }
    // {
      fprintd = {
        control = "sufficient";
        inherit (loginAuth.fprintd) modulePath;
        # Finite: the greeter disables input while a PAM reply is pending
        args = ["timeout=30" "max-tries=3"];
        order = 11200;
      };
      # requisite: an empty token must never reach the password rules
      fprintd-deny = {
        control = "requisite";
        modulePath = pamModule "pam_deny";
        order = 11300;
      };
    };

  jump = builtins.length (builtins.attrNames fingerprintRules);

  namesByOrder = rules: lib.sort (a: b: rules.${a}.order < rules.${b}.order) (builtins.attrNames rules);

  uncoveredLoginRules = lib.subtractLists ["fprintd-lid-check" "fprintd" "unix-early" "gnome_keyring" "unix" "deny"] (builtins.attrNames (lib.filterAttrs (_: r: r.enable) loginAuth));
in {
  config = lib.mkIf config.services.greetd.enable {
    # Gated below the service name: an mkIf on login's options around
    # security.pam.services.greetd itself recurses through that attrset.
    security.pam.services.greetd.rules.auth = lib.mkIf login.fprintAuth (
      fingerprintRules
      // {
        login.enable = false;
        authtok-nonempty = {
          control = "[success=${toString jump} ignore=ignore default=ignore]";
          modulePath = pamModule "pam_exec";
          args = ["quiet" "quiet_log" "expose_authtok" "${authtokNonEmpty}"];
          order = 11000;
        };
        gnome_keyring = {
          inherit (loginAuth.gnome_keyring) enable control modulePath;
          order = 12200;
        };
        # No nullok: neither "" nor a conversation abort may authenticate
        unix = {
          control = "sufficient";
          inherit (loginAuth.unix) modulePath;
          args = ["likeauth" "try_first_pass"];
          order = 13100;
        };
        deny = {
          control = "required";
          modulePath = pamModule "pam_deny";
          order = 13900;
        };
      }
    );

    assertions = lib.mkIf login.fprintAuth [
      {
        assertion =
          namesByOrder (lib.filterAttrs (_: r: r.enable && r.order < 12000) config.security.pam.services.greetd.rules.auth)
          == ["authtok-nonempty"] ++ namesByOrder fingerprintRules;
        message = "greetd-pam: authtok-nonempty must be greetd's first auth rule and jump exactly over the fingerprint block (${toString jump} rules)";
      }
      # greetd's chain is a copy of login's, so a login auth rule missing from it
      # would protect TTY logins but silently skip the greeter
      {
        assertion = uncoveredLoginRules == [];
        message = "greetd-pam: login enables auth rules greetd's own chain does not carry: ${toString uncoveredLoginRules}; add them to greetd-pam.nix";
      }
    ];
  };
}
