# Quattro Files

Quattro Files is a fast, keyboard-first visual filesystem browser for the
Omarchy Quattro shell. It browses files in place—there is no import step, no
library, and no copying of user media.

## Requirements

- Omarchy 4 / the current Quattro plugin host
- Qt 6 with QtMultimedia and its FFmpeg backend
- Python 3.11 or newer (standard library only)
- `ffmpeg` and `ffprobe`
- `inotify-tools`, `gio`, `xdg-open`, and `wl-copy`
- Optional: ImageMagick improves fallback decoding for formats FFmpeg rejects

These are present on a standard current Omarchy installation. The helper has
no network access and uses argument arrays for every external process.

## Install

From a published git repository (replace `<repository-url>` with this
repository's clone URL):

```bash
omarchy plugin add <repository-url> --enable
```

For local development from this checkout:

```bash
mkdir -p ~/.config/omarchy/plugins
ln -s "$(pwd)" ~/.config/omarchy/plugins/quattro.files
```

Then validate, rescan, and enable it:

```bash
# Validate the real checkout, not the development symlink (the validator
# intentionally rejects symlinks inside the path it validates).
omarchy plugin validate "$(pwd)"
omarchy shell shell rescanPlugins
omarchy plugin enable quattro.files
```

Install the included desktop entry to make **Quattro Files** searchable in
Omarchy's Apps launcher:

```bash
install -Dm644 data/quattro-files.desktop ~/.local/share/applications/quattro-files.desktop
```

## Launch

```bash
omarchy shell shell toggle quattro.files '{}'
```

Open a particular directory:

```bash
omarchy shell shell summon quattro.files '{"path":"/home/me/Pictures"}'
```

Recommended Hyprland binding (add this through your normal user bindings,
without replacing an existing `SUPER+E` binding):

```lua
o.bind("SUPER + E", "Quattro Files", "omarchy shell shell toggle quattro.files '{}'")
```

After editing user Hyprland bindings, run `hyprctl reload` and
`hyprctl configerrors`.

## Keyboard

| Key | Action |
| --- | --- |
| `h j k l` or arrows | Move selection through the masonry layout |
| `Enter` or `o` | Open folder; Quick Look media; open other files |
| `Space` | Open Quick Look |
| `gg` / `G` | Select first / last item |
| `Ctrl+U` / `Ctrl+D` | Scroll half a page |
| `Backspace` | Parent directory |
| `H` / `L` | Back / forward |
| `gh` / `gp` | Home / Pictures |
| `/` or `Ctrl+F` | Filter current folder |
| `c` | Open the fuzzy directory jumper |
| `Ctrl+L` | Edit location |
| `.` or `Ctrl+H` | Toggle hidden files |
| `y` | Copy selected path |
| `r` / `R` | Rename / refresh |
| `d` | Move to Trash after confirmation |
| `s` | Show or hide the sidebar |
| `Shift+S` | Browser settings |
| `+` / `-` (or `=` / `-`) | Increase / decrease thumbnail size |
| `Shift` + `+` / `Shift` + `-` | Increase / decrease grid gap |
| `F11` | Toggle fullscreen for the current workspace |
| `q` or `Escape` | Close transient UI or the browser |
| `?` | Show the complete keyboard reference |

Quick Look adds these controls:

| Key | Action |
| --- | --- |
| `q` or `Escape` | Close Quick Look |
| `Space` | Close an image, or play/pause a video |
| `[` / `]` or `Shift+Left` / `Shift+Right` | Previous / next media in current sort order |
| `Left` / `Right` or `h` / `l` | Previous/next image at any zoom; seek video ±5 seconds |
| `j` / `k` / `l` on video | Seek −10 seconds / play-pause / seek +5 seconds |
| `m` | Mute/unmute video |
| `f` or `0` | Fit image to the preview |
| `1` | Show the image at true 100% |
| `+` / `-` | Zoom image in/out |
| Mouse wheel | Zoom around the pointer |
| Mouse drag | Pan a zoomed image |
| `c` or `Tab` | Hide/show Quick Look controls |

The image or video now uses the complete Quick Look canvas. Controls sit over
the media instead of reserving a footer; hide them with `c`, `Tab`, or the Hide
button. The default fit view never enlarges an image beyond its native
resolution; explicit zoom remains available. Double-click an image to toggle
between fit and 100%.

Right-click an item for Open, Open with default, Copy path, Rename, and Move to
Trash. Permanent deletion is intentionally unavailable.

An active folder filter always keeps its input visible and shows the term in
the empty state. Navigating to another directory clears the filter so it cannot
silently hide that directory's contents.

Press `c` for a native fzf-style directory jumper. It asynchronously scans a
bounded five-level directory tree under Home (or the current non-Home root),
streams results progressively, fuzzy-ranks as you type, and supports arrows or
`Ctrl+N`/`Ctrl+P` plus Enter. The scan runs only when the jumper is opened.

## Window and settings

Quattro Files is a normal Hyprland toplevel, so it tiles, resizes, and stays on
the workspace where it was opened. This avoids the all-workspace behavior of a
layer-shell overlay. Use `F11` or the toolbar button when you want the original
fullscreen browsing experience.

The gear button (or `Shift+S`) opens global browser settings for continuously
adjustable thumbnail width, grid gap, sidebar width, filename visibility, and
folders-first sorting. A compact thumbnail slider also appears directly in the
toolbar when the window is wide enough. Appearance and browsing preferences
persist between launches.

## Architecture and data

The QML panel runs inside the existing `omarchy-shell` and owns a supported
Quickshell `FloatingWindow`; it is not a duplicate shell. A small persistent
Python helper streams directory entries and performs probing/thumbnail work on
three bounded worker threads. Only tiles inside a one-viewport overscan region
exist as QML objects, so directories containing thousands of files do not
instantiate thousands of image delegates.

Disposable thumbnails are stored under
`$XDG_CACHE_HOME/quattro-files/thumbs` (falling back to
`~/.cache/quattro-files/thumbs`). Cache keys include path, size, nanosecond
mtime, and target width. Convenience state is stored under
`$XDG_STATE_HOME/quattro-files/state.json`.

Removing either directory is safe. Quattro Files never stores original media.

## Remove

```bash
omarchy plugin remove quattro.files --yes
rm -rf ~/.cache/quattro-files ~/.local/state/quattro-files
rm ~/.local/share/applications/quattro-files.desktop
```

The final cache/state cleanup is optional and should only be run if those exact
paths are the intended targets.

## Scope

The MVP previews images, animated GIFs, and video. Generic files remain
browsable and open with the system default application. PDF/text Quick Look,
global indexing, tags, network-share setup, permanent deletion, and recursive
search are intentionally outside this release.
