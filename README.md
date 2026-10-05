# omarchy-neko

Omarchy bar widget + panel for [Neko](https://github.com/RakhaYandra/neko),
the little OpenCode companion for Linux.

## Install

```sh
omarchy plugin add https://github.com/RakhaYandra/omarchy-neko.git --enable
omarchy bar move rakha.neko right   # left | center | right, your choice
```

Requires the Neko app installed (it owns session state; the widget only
mirrors it). Without Neko running, the widget shows a placeholder.

## What it shows

- Dot: worst live state (amber = permission/question waiting, blue = working,
  green = done, red = error, grey = idle/offline).
- Badge: number of waiting requests (permissions + questions).
- Click: companion panel with sessions, permission cards (Allow / Always /
  Deny), and question cards (tap to answer, checkboxes + submit for
  multi-select, dismiss). Replies run `neko reply …` under the hood, so the
  `neko` binary must be on `PATH` (the `.deb` provides it; a dev symlink to
  `target/debug/neko` works too).
- The panel auto-closes when everything resolves.

## Status

Live widget + companion panel. Question cards arrive with Neko WS3.
