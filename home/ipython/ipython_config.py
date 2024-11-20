# Configuration file for ipython.
from pygments.styles import get_style_by_name
from pygments.util import ClassNotFound

c = get_config()  # type: ignore[name-defined]  

c.InteractiveShell.confirm_exit = False
c.InteractiveShell.separate_in = ''
c.TerminalIPythonApp.display_banner = False

c.TerminalInteractiveShell.editing_mode = 'vi'
c.TerminalInteractiveShell.editor = 'nvim'
c.TerminalInteractiveShell.true_color = True
try:
    c.TerminalInteractiveShell.highlighting_style = get_style_by_name("catppuccin-mocha")
except ClassNotFound as ex:
    print(f"Failed to set theme: {ex}")
