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

- Dot: worst live state (amber = permission waiting, blue = working,
  green = done, red = error, grey = idle/offline).
- Badge: number of pending permission requests.
- Click: companion panel with sessions + Allow / Always / Deny buttons.
  The panel auto-closes when permissions resolve. Replies run
  `neko reply permission …` under the hood.

## Status

Live widget + companion panel. Question cards arrive with Neko WS3.
