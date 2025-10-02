# Configuration file for ipython.

c = get_config()  # type: ignore[name-defined] # noqa: F821

c.InteractiveShell.confirm_exit = False
c.InteractiveShell.separate_in = ""
c.TerminalIPythonApp.display_banner = False

c.TerminalInteractiveShell.editing_mode = "vi"
c.TerminalInteractiveShell.editor = "nvim"
c.TerminalInteractiveShell.true_color = True

# IPython 9.0+ uses the new theming system
c.TerminalInteractiveShell.highlighting_style_overrides = {}
try:
    from pygments_catppuccin import MochaStyle
    c.TerminalInteractiveShell.highlighting_style_overrides = MochaStyle.styles
except ImportError:
    pass  # Fall back to default theme if catppuccin not available
