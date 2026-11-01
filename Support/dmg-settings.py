# dmgbuild settings for the release DMG; see `make dmg`. Geometry matches
# Support/make-dmg-background.swift.
import os.path

app = defines.get("app", "build/Fyxel.app")  # noqa: F821 (provided by dmgbuild)
appname = os.path.basename(app)

format = "ULFO"
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}
# No hide_extensions: it writes FinderInfo onto the bundle, which breaks `codesign --verify
# --strict` (Gatekeeper may then call the app damaged). Finder hides ".app" anyway.

background = defines.get("background", "build/dmg-background.tiff")  # noqa: F821
window_rect = ((200, 140), (640, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 112
text_size = 13
icon_locations = {appname: (170, 190), "Applications": (470, 190)}
