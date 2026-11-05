{config, ...}: let
  inherit (config.theme) palette;

  mkBtopTheme = p: ''
    theme[main_bg]="${p.base}"
    theme[main_fg]="${p.text}"
    theme[title]="${p.text}"
    theme[hi_fg]="${p.blue}"
    theme[selected_bg]="${p.surface1}"
    theme[selected_fg]="${p.blue}"
    theme[inactive_fg]="${p.overlay1}"
    theme[graph_text]="${p.rosewater}"
    theme[meter_bg]="${p.surface1}"
    theme[proc_misc]="${p.rosewater}"

    # Box outline colors
    theme[cpu_box]="${p.mauve}"
    theme[mem_box]="${p.green}"
    theme[net_box]="${p.maroon}"
    theme[proc_box]="${p.blue}"
    theme[div_line]="${p.overlay0}"

    # Gradient: temp (green->red), cpu (teal->lavender)
    theme[temp_start]="${p.green}"
    theme[temp_mid]="${p.yellow}"
    theme[temp_end]="${p.red}"
    theme[cpu_start]="${p.teal}"
    theme[cpu_mid]="${p.sapphire}"
    theme[cpu_end]="${p.lavender}"

    # Gradient: free (mauve->blue), cached (sapphire->lavender)
    theme[free_start]="${p.mauve}"
    theme[free_mid]="${p.lavender}"
    theme[free_end]="${p.blue}"
    theme[cached_start]="${p.sapphire}"
    theme[cached_mid]="${p.blue}"
    theme[cached_end]="${p.lavender}"

    # Gradient: available (peach->red), used (green->sky)
    theme[available_start]="${p.peach}"
    theme[available_mid]="${p.maroon}"
    theme[available_end]="${p.red}"
    theme[used_start]="${p.green}"
    theme[used_mid]="${p.teal}"
    theme[used_end]="${p.sky}"

    # Gradient: download (peach->red), upload (green->sky), process (sapphire->mauve)
    theme[download_start]="${p.peach}"
    theme[download_mid]="${p.maroon}"
    theme[download_end]="${p.red}"
    theme[upload_start]="${p.green}"
    theme[upload_mid]="${p.teal}"
    theme[upload_end]="${p.sky}"
    theme[process_start]="${p.sapphire}"
    theme[process_mid]="${p.lavender}"
    theme[process_end]="${p.mauve}"
  '';
in {
  programs.btop = {
    enable = true;
    settings = {
      vim_keys = true;
      color_theme = "${palette.dark.name}"; # Default, theme-toggle switches this
    };
  };

  xdg.configFile = {
    "btop/themes/${palette.dark.name}.theme".text = mkBtopTheme palette.dark;
    "btop/themes/${palette.light.name}.theme".text = mkBtopTheme palette.light;
  };
}
