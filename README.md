# rofiphist

`rofiphist.sh` is a small Bash launcher for browsing and managing
[`cliphist`](https://github.com/sentriz/cliphist) clipboard history through
[`rofi`](https://github.com/davatorium/rofi).

The script opens an interactive rofi menu with clipboard history entries. Press
`Enter` to decode the selected entry and copy it back to the clipboard with
`wl-copy`. Press `Alt+Enter` to open an actions menu where you can copy, copy
and delete, or delete the selected history item. The main menu also includes
maintenance commands for wiping or compacting the cliphist database.

## Requirements

- `rofi`
- `cliphist`
- `wl-copy` from `wl-clipboard`
- `awk` and `xargs`

## Usage

```sh
./rofiphist.sh
```

Use a custom rofi theme:

```sh
./rofiphist.sh --theme /path/to/theme.rasi
```

Show help:

```sh
./rofiphist.sh --help
```

### Use a key remapper to launch the script

#### [xremap](https://github.com/xremap/xremap)

```yml
keymap:
 
  - name: Global Remaps
    remap:
      Shift-Alt-v:
        launch:
          - "bash"
          - "-c"
          - "/path/to/rofiphist.sh"
```

By default, the script uses `rounded-nord-dark.rasi` rofi theme from the same directory as
the script. This default theme comes from the
[rofi-themes-collection](https://github.com/newmanls/rofi-themes-collection)
project.
