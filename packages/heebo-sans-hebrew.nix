# Heebo pinned to weight 400 and renamed "Heebo Sans Hebrew", for zapfast.
# zapfast (fastframe-fonts) picks its Hebrew fallback by scanning font files,
# favouring families that name the script and say "sans", and it draws a
# variable font at its default instance. Noto Sans Hebrew's default is Thin,
# and the variable Heebo loses on the name; a static regular face with both
# words in its name wins and renders at a normal weight.
{
  google-fonts,
  python3,
  runCommand,
}: let
  heebo = google-fonts.override {fonts = ["Heebo"];};
  python = python3.withPackages (p: [p.fonttools]);
in
  runCommand "heebo-sans-hebrew" {nativeBuildInputs = [python];} ''
    mkdir -p $out/share/fonts/truetype
    fonttools varLib.instancer "${heebo}/share/fonts/truetype/Heebo[wght].ttf" wght=400 \
      -o instance.ttf
    python3 -I - instance.ttf $out/share/fonts/truetype/HeeboSansHebrew-Regular.ttf <<'EOF'
    import sys
    from fontTools.ttLib import TTFont

    font = TTFont(sys.argv[1])
    names = font["name"]
    for name_id in (16, 17, 25):
        names.removeNames(nameID=name_id)
    for name_id, value in {
        1: "Heebo Sans Hebrew",
        2: "Regular",
        4: "Heebo Sans Hebrew Regular",
        6: "HeeboSansHebrew-Regular",
    }.items():
        names.setName(value, name_id, 3, 1, 0x409)
        names.setName(value, name_id, 1, 0, 0)
    font.save(sys.argv[2])
    EOF
  ''
