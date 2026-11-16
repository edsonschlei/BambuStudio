#!/usr/bin/env bash
#
# Build native Debian/Ubuntu packages for BambuStudio (no AppImage, no Flatpak).
#
# Produces:
#   bambustudio_<version>_<arch>.deb          - the application
#   bambustudio-dbgsym_<version>_<arch>.ddeb  - detached debug symbols
#
# The application is installed according to the FHS:
#   /usr/bin/bambu-studio                          launcher
#   /usr/lib/<triplet>/bambu-studio/               real binary + bundled FFmpeg
#   /usr/share/BambuStudio/                        resources
#   /usr/share/applications/BambuStudio.desktop
#   /usr/share/icons/hicolor/*/apps/BambuStudio.png
#   /usr/share/metainfo/com.bambulab.BambuStudio.metainfo.xml
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Defaults / CLI
# ---------------------------------------------------------------------------
WORK="${WORK:-$ROOT/package-work}"
JOBS="${JOBS:-$(nproc)}"
SKIP_DEPS=0
SKIP_CHECKS=0
CLEAN=0
VERSION_OVERRIDE=""
MAINTAINER="${DEB_MAINTAINER:-BambuStudio Maintainer <bambustudio@users.noreply.github.com>}"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --workdir DIR      Build/staging directory (default: $ROOT/package-work)
  --jobs N           Parallel build jobs (default: nproc = $(nproc))
  --version VER      Override the Debian version (default: derived from version.inc)
  --maintainer STR   Debian maintainer field
  --skip-deps        Reuse an existing dependency build in WORK/deps-destdir
  --skip-checks      Skip memory/disk preflight checks
  --clean            Remove WORK before starting
  -h, --help         Show this help

The target architecture and distribution are taken from the running system.
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '\n==> %s\n' "$*"; }

while (($#)); do
    case "$1" in
        --workdir)     WORK="$2"; shift 2 ;;
        --jobs)        JOBS="$2"; shift 2 ;;
        --version)     VERSION_OVERRIDE="$2"; shift 2 ;;
        --maintainer)  MAINTAINER="$2"; shift 2 ;;
        --skip-deps)   SKIP_DEPS=1; shift ;;
        --skip-checks) SKIP_CHECKS=1; shift ;;
        --clean)       CLEAN=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             die "Unknown option: $1 (try --help)" ;;
    esac
done

# ---------------------------------------------------------------------------
# Environment detection (target = the machine running this script)
# ---------------------------------------------------------------------------
# shellcheck disable=SC1091
. /etc/os-release
ARCH="$(dpkg --print-architecture)"
TRIPLET="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
[[ "$ARCH" == "amd64" ]] || die "This packaging setup targets amd64 (detected: $ARCH)"

command -v cmake >/dev/null || die "cmake is required"
command -v ninja >/dev/null || die "ninja-build is required"
command -v objcopy >/dev/null || die "binutils (objcopy) is required"
command -v readelf >/dev/null || die "binutils (readelf) is required"
command -v dpkg-deb >/dev/null || die "dpkg-deb is required"
command -v dpkg-shlibdeps >/dev/null || die "dpkg-dev is required"

if ((CLEAN)); then
    log "Cleaning $WORK"
    rm -rf "$WORK"
fi
mkdir -p "$WORK"

if ((SKIP_CHECKS)); then
    log "Skipping memory/disk preflight checks"
else
    FREE_MEM_GB=$(free -g -t | awk '/^Mem:/ {print $NF}')
    FREE_DISK_KB=$(df -k "$WORK" | awk 'NR==2 {print $4}')
    ((FREE_MEM_GB >= 10)) || printf 'WARNING: >=10 GB free RAM recommended (found %s GB); use --skip-checks to override\n' "$FREE_MEM_GB" >&2
    ((FREE_DISK_KB >= 10*1024*1024)) || printf 'WARNING: >=10 GB free disk recommended (found %s GiB)\n' "$((FREE_DISK_KB/1024/1024))" >&2
fi

# ---------------------------------------------------------------------------
# Version / package metadata
# ---------------------------------------------------------------------------
RAW_VERSION="${VERSION_OVERRIDE:-}"
if [[ -z "$RAW_VERSION" ]]; then
    RAW_VERSION="$(sed -n 's/^[[:space:]]*set(SLIC3R_VERSION[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/version.inc" | head -1)"
fi
[[ -n "$RAW_VERSION" ]] || die "Could not determine version from version.inc"

# Normalise 02.09.01.70 -> 2.9.1.70 (leading zeroes are not wanted in a deb version)
UPSTREAM_VERSION="$(awk -F. '{
    for (i = 1; i <= NF; i++) { sub(/^0+/, "", $i); if ($i == "") $i = "0" }
    printf "%s", $1
    for (i = 2; i <= NF; i++) printf ".%s", $i
    printf "\n"
}' <<<"$RAW_VERSION")"

DEB_VERSION="${UPSTREAM_VERSION}-1~ubuntu${VERSION_ID}.1"
DATE_UTC="$(LC_ALL=C date -u +%Y-%m-%d)"
ARCHIVE_DATE="$(LC_ALL=C date -R)"

log "Upstream version: $RAW_VERSION -> $UPSTREAM_VERSION"
log "Debian version:   $DEB_VERSION"
log "Target:           Ubuntu $VERSION_ID ($VERSION_CODENAME), $ARCH/$TRIPLET"
log "Work directory:   $WORK"

# ---------------------------------------------------------------------------
# 1. Update submodules if needed
# ---------------------------------------------------------------------------
if [[ ! -d "$ROOT/resources/profiles/BBL" ]]; then
    log "Fetching git submodules (resources/profiles)"
    git -C "$ROOT" submodule update --init --recursive
else
    log "Submodules already present"
fi

# ---------------------------------------------------------------------------
# 2. Build bundled dependencies
# ---------------------------------------------------------------------------
DEPS_PREFIX="$WORK/deps-destdir/usr/local"
if ((SKIP_DEPS)); then
    [[ -d "$DEPS_PREFIX" ]] || die "--skip-deps given but $DEPS_PREFIX does not exist"
    log "Reusing dependencies at $DEPS_PREFIX"
else
    log "Configuring dependencies"
    cmake -S "$ROOT/deps" -B "$WORK/deps" -G Ninja \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_BUILD_TYPE=Release \
        -DDESTDIR="$WORK/deps-destdir" \
        -DDEP_WX_GTK3=ON
    log "Building dependencies"
    cmake --build "$WORK/deps" --parallel "$JOBS"
fi

# ---------------------------------------------------------------------------
# 3. Build BambuStudio with FHS layout
# ---------------------------------------------------------------------------
log "Configuring BambuStudio (FHS / native layout)"
cmake -S "$ROOT" -B "$WORK/build" -G Ninja \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_PREFIX_PATH="$DEPS_PREFIX" \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_BINDIR="lib/$TRIPLET/bambu-studio" \
    -DSLIC3R_STATIC=ON \
    -DSLIC3R_GTK=3 \
    -DSLIC3R_FHS=ON \
    -DBBL_RELEASE_TO_PUBLIC=1 \
    -DBBL_INTERNAL_TESTING=0 \
    -DCMAKE_BUILD_TYPE=Release

log "Building BambuStudio"
cmake --build "$WORK/build" --target BambuStudio --parallel "$JOBS"

BIN="$WORK/build/src/bambu-studio"
[[ -x "$BIN" ]] || die "Expected binary $BIN was not produced"

# The FFmpeg shared libraries are copied into the build tree at configure time
# by bambustudio_copy_sos(). Fail early if that upstream behaviour changed.
FFMPEG_LIBS=(libavcodec.so.61 libavutil.so.59 libswresample.so.5 libswscale.so.8)
for lib in "${FFMPEG_LIBS[@]}"; do
    [[ -e "$WORK/build/src/$lib" ]] || die "Missing $WORK/build/src/$lib - upstream FFmpeg copy changed; check deps build"
done

# ---------------------------------------------------------------------------
# 4. Split detached debug symbols (before staging the stripped binaries)
# ---------------------------------------------------------------------------
DBGSTAGE="$WORK/dbgstage"
rm -rf "$DBGSTAGE"
DEBUG_OUTPUT="$DBGSTAGE/usr/lib/debug"
BID_LIST=""

split_debug() {
    local file="$1" rel="$2" bid out_dir link_dir link_target
    out_dir="$DEBUG_OUTPUT/$(dirname "$rel")"
    mkdir -p "$out_dir"

    # objcopy stores the debuglink name as given; use a relative name so gdb
    # finds the file via the build-id even after installation.
    (
        cd "$DEBUG_OUTPUT"
        objcopy --only-keep-debug "$file" "$rel.debug"
        objcopy --strip-debug "$file"
        objcopy --add-gnu-debuglink="$rel.debug" "$file"
    )

    bid="$(readelf -n "$file" | awk '/Build ID:/ {print $3; exit}')"
    [[ -n "$bid" ]] || die "No GNU build-id found in $file (needed for debug symbol lookup)"
    BID_LIST+="${BID_LIST:+ }$bid"

    link_dir="$DEBUG_OUTPUT/.build-id/${bid:0:2}"
    mkdir -p "$link_dir"
    link_target="$(realpath -m --relative-to="$link_dir" "$DEBUG_OUTPUT/$rel.debug")"
    ln -sfn "$link_target" "$link_dir/${bid:2}.debug"
    log "  debug: $rel.debug (build-id $bid)"
}

log "Splitting debug symbols"
split_debug "$BIN" "usr/lib/$TRIPLET/bambu-studio/bambu-studio"
for lib in "$WORK"/build/src/libav*.so.*; do
    [[ -e "$lib" ]] || continue
    # Only split libraries that actually carry debug info and a build-id,
    # otherwise gdb could not locate the detached file after installation.
    if readelf -S "$lib" 2>/dev/null | grep -q '\.debug_info' \
       && readelf -n "$lib" 2>/dev/null | grep -q 'Build ID:'; then
        split_debug "$lib" "usr/lib/$TRIPLET/bambu-studio/$(basename "$lib")"
    fi
done

# ---------------------------------------------------------------------------
# 5. Stage the FHS install
# ---------------------------------------------------------------------------
STAGE="$WORK/stage"
rm -rf "$STAGE"
log "Staging install into $STAGE"
DESTDIR="$STAGE" cmake --install "$WORK/build"

PRIV_LIBDIR="$STAGE/usr/lib/$TRIPLET/bambu-studio"
mkdir -p "$PRIV_LIBDIR"

# Upstream installs the bundled FFmpeg libraries to ${prefix}/bin (/usr/bin),
# which is not acceptable for a native package. Move them next to the binary
# so the $ORIGIN RPATH resolves them.
shopt -s nullglob
av_libs=("$STAGE"/usr/bin/libavcodec.so* "$STAGE"/usr/bin/libavutil.so* \
         "$STAGE"/usr/bin/libswresample.so* "$STAGE"/usr/bin/libswscale.so*)
shopt -u nullglob
((${#av_libs[@]})) || die "No FFmpeg libraries found in $STAGE/usr/bin - install layout changed"
mv -- "${av_libs[@]}" "$PRIV_LIBDIR/"

[[ -x "$PRIV_LIBDIR/bambu-studio" ]] || die "Binary was not installed to $PRIV_LIBDIR"

readelf -d "$PRIV_LIBDIR/bambu-studio" | grep -F '$ORIGIN' >/dev/null \
    || die "Expected \$ORIGIN RPATH on the installed binary"

# Public launcher
install -d "$STAGE/usr/bin"
cat > "$STAGE/usr/bin/bambu-studio" <<EOF
#!/bin/sh
# Launcher for the natively packaged BambuStudio.
exec /usr/lib/$TRIPLET/bambu-studio/bambu-studio "\$@"
EOF
chmod 755 "$STAGE/usr/bin/bambu-studio"

# Desktop entry / icons / resources are installed by CMake's FHS install rules.
[[ -f "$STAGE/usr/share/applications/BambuStudio.desktop" ]] || die "Desktop file missing from stage"
[[ -d "$STAGE/usr/share/BambuStudio" ]] || die "Resources missing from stage"
if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$STAGE/usr/share/applications/BambuStudio.desktop" \
        || die "Desktop file failed validation"
fi

# AppStream metadata
install -d "$STAGE/usr/share/metainfo"
sed -e "s|@VERSION@|$UPSTREAM_VERSION|g" -e "s|@DATE@|$DATE_UTC|g" \
    "$SCRIPT_DIR/com.bambulab.BambuStudio.metainfo.xml.in" \
    > "$STAGE/usr/share/metainfo/com.bambulab.BambuStudio.metainfo.xml"
if command -v appstreamcli >/dev/null 2>&1; then
    appstreamcli validate --no-net "$STAGE/usr/share/metainfo/com.bambulab.BambuStudio.metainfo.xml" \
        || die "AppStream metadata failed validation"
fi

# Documentation / licence
install -d "$STAGE/usr/share/man/man1"
gzip -9n -c "$SCRIPT_DIR/bambu-studio.1" > "$STAGE/usr/share/man/man1/bambu-studio.1.gz"
install -d "$STAGE/usr/share/doc/bambustudio"
{
    cat "$SCRIPT_DIR/copyright.header"
    printf '\n'
    cat "$ROOT/LICENSE"
} > "$STAGE/usr/share/doc/bambustudio/copyright"
{
    printf 'bambustudio (%s) unstable; urgency=medium\n\n' "$DEB_VERSION"
    printf '  * Native Ubuntu package of upstream BambuStudio %s.\n\n' "$UPSTREAM_VERSION"
    printf ' -- %s  %s\n' "$MAINTAINER" "$ARCHIVE_DATE"
} | gzip -9n > "$STAGE/usr/share/doc/bambustudio/changelog.Debian.gz"

# ---------------------------------------------------------------------------
# 6. Determine runtime dependencies
# ---------------------------------------------------------------------------
log "Computing runtime dependencies with dpkg-shlibdeps"
SHLIB_DIR="$WORK/shlibdeps"
rm -rf "$SHLIB_DIR"
mkdir -p "$SHLIB_DIR/debian"
SHLIB_BIN="$SHLIB_DIR/bambustudio/usr/lib/$TRIPLET/bambu-studio"
mkdir -p "$SHLIB_BIN"
cat > "$SHLIB_DIR/debian/control" <<EOF
Source: bambustudio
Section: graphics
Priority: optional
Maintainer: $MAINTAINER
Standards-Version: 4.7.0

Package: bambustudio
Architecture: $ARCH
Depends:
Description: placeholder
 placeholder
EOF
cp "$PRIV_LIBDIR/bambu-studio" "$SHLIB_BIN/"
cp "$PRIV_LIBDIR"/libav*.so* "$SHLIB_BIN/" 2>/dev/null || true

SHLIBS="$(cd "$SHLIB_DIR" && dpkg-shlibdeps -O --ignore-missing-info \
    bambustudio/usr/lib/$TRIPLET/bambu-studio/* 2>"$WORK/shlibdeps.log" \
    | sed -n 's/^shlibs:Depends=//p')"
[[ -n "$SHLIBS" ]] || { cat "$WORK/shlibdeps.log" >&2; die "dpkg-shlibdeps produced no dependencies"; }

# Libraries that are dlopen()ed at runtime are invisible to dpkg-shlibdeps.
# Names below are the runtime package names on Ubuntu 26.04 (resolute).
EXPLICIT_DEPS=(
    libgtk-3-0t64
    libwebkit2gtk-4.1-0
    libsoup-3.0-0
    libgstreamer1.0-0
    libgstreamer-plugins-base1.0-0
    gstreamer1.0-plugins-bad
    libdbus-1-3
    libudev1
    libsecret-1-0
    libosmesa6
    libglu1-mesa
    libwayland-client0
    libxkbcommon0
    libcurl4t64
    libexpat1
    libpng16-16t64
    zlib1g
    libbz2-1.0
)

declare -A SEEN=()
IFS=', ' read -r -a SHLIB_ARRAY <<<"$SHLIBS"
for dep in "${SHLIB_ARRAY[@]}"; do
    name="${dep%% *}"
    [[ -n "$name" ]] && SEEN["$name"]=1
done

ALL_DEPS="$SHLIBS"
for dep in "${EXPLICIT_DEPS[@]}"; do
    name="${dep%% *}"
    if [[ -z "${SEEN[$name]:-}" ]]; then
        ALL_DEPS+=", $dep"
        SEEN["$name"]=1
    fi
done
log "Depends: $ALL_DEPS"

# ---------------------------------------------------------------------------
# 7. Debian control + maintainer scripts
# ---------------------------------------------------------------------------
install -d -m 755 "$STAGE/DEBIAN"
sed -e "s|@VERSION@|$DEB_VERSION|g" \
    -e "s|@ARCH@|$ARCH|g" \
    -e "s|@MAINTAINER@|$MAINTAINER|g" \
    -e "s|@DEPENDS@|$ALL_DEPS|g" \
    "$SCRIPT_DIR/control.in" > "$STAGE/DEBIAN/control"

for script in postinst postrm; do
    install -m 755 "$SCRIPT_DIR/$script" "$STAGE/DEBIAN/$script"
done

# ---------------------------------------------------------------------------
# 8. Detached debug symbol package
# ---------------------------------------------------------------------------
install -d -m 755 "$DBGSTAGE/DEBIAN"
cat > "$DBGSTAGE/DEBIAN/control" <<EOF
Package: bambustudio-dbgsym
Version: $DEB_VERSION
Architecture: $ARCH
Section: debug
Priority: optional
Package-Type: ddeb
Auto-Built-Package: debug-symbols
Depends: bambustudio (= $DEB_VERSION)
Build-Ids: $BID_LIST
Maintainer: $MAINTAINER
Homepage: https://github.com/bambulab/BambuStudio
Description: debug symbols for bambustudio
 Detached debugging symbols for the natively packaged BambuStudio binary and
 its bundled FFmpeg libraries, suitable for gdb with the build-id lookup.
EOF

# ---------------------------------------------------------------------------
# 9. Normalise permissions and build the packages
# ---------------------------------------------------------------------------
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE/DEBIAN" -type f -exec chmod 644 {} +
find "$STAGE/usr/share" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/usr/bin/bambu-studio" "$PRIV_LIBDIR/bambu-studio"

find "$DBGSTAGE" -type d -exec chmod 755 {} +
find "$DBGSTAGE/DEBIAN" -type f -exec chmod 644 {} +

DEB_FILE="$WORK/bambustudio_${DEB_VERSION}_${ARCH}.deb"
DDEB_FILE="$WORK/bambustudio-dbgsym_${DEB_VERSION}_${ARCH}.ddeb"
log "Building $DEB_FILE"
dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$DEB_FILE"
log "Building $DDEB_FILE"
dpkg-deb --root-owner-group -Zxz --build "$DBGSTAGE" "$DDEB_FILE"

# ---------------------------------------------------------------------------
# 10. Report / verification hints
# ---------------------------------------------------------------------------
log "Packages built:"
ls -lh "$DEB_FILE" "$DDEB_FILE"
cat <<EOF

Next steps:
  dpkg-deb --info  "$DEB_FILE"
  dpkg-deb --contents "$DEB_FILE" | less
  lintian "$DEB_FILE" "$DDEB_FILE" || true
  sudo apt install "$DEB_FILE"
EOF
