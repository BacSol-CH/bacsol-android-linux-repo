# bacsol-android-linux-repo

Build recipes and clean source snapshots for the BacSol Android/Linux craft apps,
laid out like [termux-packages](https://github.com/termux/termux-packages): one
repository, one directory per package, each holding its own recipe.

## Layout

```
packages/<craft>/
  build.sh      termux-style recipe (SRCURL + SHA256 pins, build steps)
  *.patch       patches auto-applied to the vendored source before building
  src/          clean tracked source snapshot at the pinned version
  UPSTREAM.md   upstream project, version pin, licence, provenance notes
  LICENSE-MIT / LICENSE-APACHE / NOTICE
```

Current packages: `wordcraft`, `gridcraft`, `deckcraft`, `pdfcraft`.

## How a build works

1. `build.sh` fetches the upstream tarball pinned by `TERMUX_PKG_SRCURL` and
   verifies `TERMUX_PKG_SHA256` (or takes `src/` as the working source).
2. Every `*.patch` file in the package directory is applied automatically to the
   prepared source, in filename order, before configuration.
3. The remaining `termux_step_*` hooks in `build.sh` do the X11-only fixups
   (wayland feature removal, vendor rewrites, android-cfg neutralisation), then
   build with cargo and install the resulting binaries.

Paths are expressed through tooling variables (`$TERMUX_PREFIX`, `$WORKDIR`) so
recipes stay host-independent.

## Licence

Each package is dual-licensed MIT or Apache-2.0 at the user's option; see the
per-package `LICENSE-MIT`, `LICENSE-APACHE` and `NOTICE`, plus `UPSTREAM.md` for
trademark and third-party attribution terms.
