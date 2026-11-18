# Native Ubuntu `.deb` packaging for BambuStudio

This directory builds a conventional Debian/Ubuntu package of BambuStudio that
runs natively on the host — **no Flatpak, no AppImage, no FUSE**.

The target distribution is detected from the running system (tested on Ubuntu
26.04 "resolute", amd64). The build uses the upstream CMake install rules with
`SLIC3R_FHS=ON` and `DESTDIR` staging, then assembles the package with
`dpkg-deb`. Upstream sources are not modified.

## Usage

From the repository root:

```sh
# Install build + packaging prerequisites once (Ubuntu 26.04):
sudo apt-get install -y \
  build-essential ninja-build cmake git pkgconf autoconf libtool texinfo m4 \
  extra-cmake-modules wayland-protocols libwayland-dev libxkbcommon-dev \
  libgl1-mesa-dev libglu1-mesa-dev libosmesa6-dev libcairo2-dev \
  libgtk-3-dev libsoup2.4-dev libwebkit2gtk-4.1-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-bad \
  libsecret-1-dev libdbus-1-dev libudev-dev libglew-dev libmspack-dev \
  libssl-dev libcurl4-openssl-dev libunwind-dev libx264-dev libbz2-dev \
  nasm yasm fakeroot dpkg-dev lintian desktop-file-utils appstream

# Build both packages:
./packaging/deb/build_deb.sh
```

Note: `libgstreamer-plugins-good1.0-dev`, listed in the upstream wiki, is not
available in Ubuntu 26.04 and is not required to build BambuStudio. Only the
runtime plugin package `gstreamer1.0-plugins-bad` is needed (for printer
liveview).

Useful options:

| Option | Purpose |
|---|---|
| `--workdir DIR` | Output/staging directory (default `package-work/`) |
| `--jobs N` | Parallel build jobs (default `nproc`) |
| `--version VER` | Override the derived Debian version |
| `--maintainer STR` | Override the `Maintainer` field |
| `--skip-deps` | Reuse a previous dependency build |
| `--skip-build` | Skip configure/compile; re-stage and re-package from an existing build tree (fast iteration on packaging changes) |
| `--skip-checks` | Skip RAM/disk preflight warnings |
| `--clean` | Delete the work directory first |

## Outputs

`package-work/` contains:

- `bambustudio_<version>_amd64.deb` — the application
- `bambustudio-dbgsym_<version>_amd64.ddeb` — detached debug symbols (gdb
  build-id lookup), produced with `objcopy --only-keep-debug`

## Installed layout

```
/usr/bin/bambu-studio                            launcher
/usr/lib/x86_64-linux-gnu/bambu-studio/          real binary + bundled FFmpeg .so files
/usr/share/BambuStudio/                          resources (profiles, images, i18n, ...)
/usr/share/applications/BambuStudio.desktop
/usr/share/icons/hicolor/{32,128,192}x*/apps/BambuStudio.png
/usr/share/metainfo/com.bambulab.BambuStudio.metainfo.xml
/usr/share/man/man1/bambu-studio.1.gz
/usr/share/doc/bambustudio/{copyright,changelog.Debian.gz}
```

The binary is built with `$ORIGIN` RPATH, so it loads the bundled FFmpeg
libraries from its private libdir. These are deliberately relocated out of
`/usr/bin`, where upstream's CMake rules would otherwise install them.
Runtime dependencies are computed with `dpkg-shlibdeps` and completed with
libraries that are only loaded at runtime (GTK3, WebKit2GTK, GStreamer, ...).

The optional non-free Bambu networking plugin is not part of this build;
SD-card printing is supported.

## Verify and install

```sh
dpkg-deb --info package-work/bambustudio_*.deb
dpkg-deb --contents package-work/bambustudio_*.deb | less
lintian package-work/bambustudio_*.deb package-work/bambustudio-dbgsym_*.ddeb || true
sudo apt install ./package-work/bambustudio_*.deb
```

To install debug symbols too:

```sh
sudo apt install ./package-work/bambustudio-dbgsym_*.ddeb
```

## Files in this directory

| File | Purpose |
|---|---|
| `build_deb.sh` | Full build automation (deps → CMake → staging → packaging) |
| `control.in` | Binary package control template |
| `postinst`, `postrm` | Maintainer scripts (update MIME/icon/desktop caches) |
| `copyright.header` | DEP-5 header; upstream `LICENSE` is appended at build time |
| `bambu-studio.1` | Man page (avoids lintian `no-manual-page`) |
| `com.bambulab.BambuStudio.metainfo.xml.in` | AppStream metadata template |
