# Dependencies & Requirements — BambuStudio

This document inventories the libraries, tools and platform requirements used by
this repository. For subsystem descriptions and agent orientation, see
[`AGENTS.md`](../AGENTS.md).

> Values below are taken from `CMakeLists.txt`, `src/CMakeLists.txt`,
> `src/libslic3r/CMakeLists.txt`, `deps/CMakeLists.txt`, `version.inc`, build scripts
> and `package.json` files. When a version is not pinned in-tree, it is marked
> *unpinned* or with the minimum version found in CMake.

---

## 1. Build tooling

| Tool | Version / requirement | Notes |
|---|---|---|
| CMake | ≥ 3.13 (root & `src/CMakeLists.txt`); ≥ 3.20 for `CMakePresets.json` | Presets are Windows MSVC only. |
| C++ compiler | C++17 (`CMAKE_CXX_STANDARD 17`, required) | MSVC (VS 2022/2026 generators in presets), Clang (macOS), GCC (Linux). GCC needs `-fext-numeric-literals` for Boost quad-float literals. |
| Ninja / Visual Studio / Make | any | Out-of-source builds recommended. |
| Perl | any modern version | Needed only for `Build.PL` and XS/Perl tests. |
| pnpm | `10.12.1` (pinned via `packageManager` in `device_page/package.json`) | For the embedded device web UI. |
| Node.js | compatible with Vite 6 / React 19 (Node ≥ 18) | Web UI build & Playwright tests. |
| Git | required | `deps/` uses `find_package(Git REQUIRED)` and `git apply` for patches. |
| Docker / Podman | optional | `Dockerfile`, `Containerfile`, `Docker*.sh`. |

Build helper scripts: `BuildLinux.sh`, `BuildMac.sh`, `BuildFedora.sh`,
`build_win.bat`, `DockerBuild.sh`, `DockerRun.sh`, `DockerEntrypoint.sh`, `Build.PL`.
Linux build requires ≥10 GB free RAM and ≥10 GB free disk by default
(override with `-r` / `-f` in `BuildLinux.sh`).

---

## 2. CMake options (build configuration)

Defined in the root `CMakeLists.txt`:

| Option | Default | Purpose |
|---|---|---|
| `SLIC3R_STATIC` | auto (1 on some platforms) | Link Boost/TBB/GLEW/curl/etc. statically. **Required on Unix** when using `deps/` output. |
| `SLIC3R_GUI` | `1` | Build GUI components (OpenGL, wxWidgets). |
| `SLIC3R_BUILD_TESTS` | `OFF` | Build C++ unit tests. |
| `SLIC3R_GTK` | `2` | GTK version used by wxWidgets on Linux. |
| `BBL_RELEASE_TO_PUBLIC` | `0` | Public/release vs. internal build behavior. |
| `BBL_INTERNAL_TESTING` | `1` (in `version.inc`) | Internal testing mode. |
| `SLIC3R_ENABLE_OPENMESHCRAFT_BOOLEAN` / `SLIC3R_ALLOW_MCUT_BOOLEAN` | — | Boolean backend selection (OpenMeshCraft preferred, MCUT fallback). |
| `DEP_BUILD_*` (in `deps/CMakeLists.txt`) | mostly `ON` | Toggle downloading/building each dependency (PNG, JPEG, TIFF, Boost, OpenSSL, GLFW, Blosc, Freetype, wxWidgets, GMP, MPFR, FFMPEG, libharu). |
| `DESTDIR` / `DEP_DOWNLOAD_DIR` | build dir | Where deps are installed / sources downloaded. |

---

## 3. External C/C++ libraries (found via CMake / `find_package`)

### 3.1 Core geometry, math & algorithms

| Library | Version | Used for |
|---|---|---|
| Boost | ≥ **1.83.0** (`MINIMUM_BOOST_VERSION`) | Asio, filesystem, geometry, iostreams, thread, etc. Components configured in root CMake. |
| CGAL | unpinned (`find_package(CGAL REQUIRED)`) | Computational geometry, boolean operations (via `libslic3r_cgal`), needs GMP/MPFR. |
| Eigen3 | ≥ 3.3 (optional find; pinned in vendored copy too) | Linear algebra. |
| TBB | unpinned (`find_package(TBB REQUIRED)`) | Parallel execution (`Execution/`, `-DUSE_TBB`). |
| GMP / MPFR | unpinned | Exact arithmetic backend for CGAL. |
| NLopt | ≥ **1.4** | Nonlinear optimization. |
| OpenVDB | ≥ **5.0** | Volumetric data (SLA support structures). |
| Qhull | unpinned (vendored + external) | Convex hulls. |
| libnest2d | vendored | 2D bin packing / auto-arrange. |
| libigl | vendored | Geometry processing. |
| libnoise | unpinned (`find_package(libnoise REQUIRED)`) | Structured (Perlin/Billow) fuzzy skin. |
| OpenMeshCraft | unpinned (CONFIG package) | Preferred mesh boolean backend. |
| MCUT | vendored (`src/mcut`) | Fallback mesh boolean backend. |
| semver, ankerl, fast_float, tinybvh | vendored | Versioning, hashing, float parsing, BVH. |

### 3.2 Mesh / model I/O

| Library | Version | Used for |
|---|---|---|
| OpenCASCADE (OCCT) | unpinned (`find_package(OpenCASCADE REQUIRED)`) | STEP/CAD import and advanced boolean ops. |
| Assimp | unpinned (`find_package(assimp REQUIRED)`) | General 3D model import. |
| OpenCV | 4.6.0-era (MSVC runtime/arch logic in `libslic3r/CMakeLists.txt`) | Image analysis, calibration, texture/color features. |
| admesh | vendored | STL repair/processing. |
| Clipper / Clipper2 | vendored | 2D polygon clipping/offsetting. |
| earcut, glu-libtess | vendored | Polygon triangulation/tessellation. |

### 3.3 GUI, rendering & platform

| Library | Version | Used for |
|---|---|---|
| wxWidgets | ≥ **3.1** (≥3.0 on Linux, GTK2/3) | Desktop UI; components: `base core adv html gl aui net media webview richtext xml`. |
| OpenGL | system | 3D viewport. |
| GLEW | unpinned | OpenGL extension loading. |
| GLFW | unpinned | Window/context management. |
| ImGui / ImGuizmo | vendored (`src/imgui`, `src/imguizmo`) | debug/overlay UI and gizmos. |
| WebView2 | Windows | Embedded web content (device page). |
| Cocoa / AVFoundation / AVKit / CoreMedia / VideoToolbox / IOKit / CoreFoundation | macOS frameworks | Native macOS integration, video decode, camera. |
| DBus, pangoft2-1.0, iconv | Linux | Desktop integration, text rendering. |
| hidapi | vendored | HID device access. |
| Shiny | vendored | C++ Profiler UI integration. |

### 3.4 Networking, serialization & compression

| Library | Version | Used for |
|---|---|---|
| CURL / libcurl | unpinned (`CURL CONFIG` or module) | HTTP downloads, printer/web communication. |
| OpenSSL | unpinned (`find_package(OpenSSL REQUIRED)`) | TLS, crypto. |
| EXPAT | optional | XML parsing. |
| cereal | unpinned (`find_package(cereal REQUIRED)`) | C++ serialization. |
| ZLIB, Blosc, miniz, minilzo, libharu | vendored / deps | Compression and PDF (libharu). |
| FFMPEG (AV codecs) | unpinned (`DEP_BUILD_FFMPEG`) | Video decoding/encoding (camera/media). |
| WebView2 / wxWebview | see above | Embedded web UI host. |

### 3.5 Images & fonts

| Library | Version | Used for |
|---|---|---|
| libpng (PNG), libjpeg (JPEG), libtiff (TIFF) | dep recipes / optional `find_package` | Image I/O. |
| FreeType | unpinned | Font rendering. |
| OpenEXR | dep recipe | HDR images. |
| nanosvg, stb_dxt | vendored | SVG parsing, texture compression. |

---

## 4. `deps/` external project catalogue

`deps/CMakeLists.txt` orchestrates these recipes (one folder each, with
platform-specific `deps-{linux,macos,windows,mingw,unix-common}.cmake`):

`Assimp`, `Blosc`, `Boost`, `CGAL`, `CURL`, `Cereal`, `EXPAT`, `FFMPEG`, `FREETYPE`,
`GLEW`, `GLFW`, `GMP`, `JPEG`, `MPFR`, `NLopt`, `OCCT`, `OpenCSG`, `OpenCV`,
`OpenEXR`, `OpenMeshCraft`, `OpenSSL`, `OpenVDB`, `PNG`, `Qhull`, `TBB`, `TIFF`,
`WebView2`, `ZLIB`, `libharu`, `libnoise`, `wxWidgets`.

Each builds into a `destdir` prefix; the main build consumes it via
`-DCMAKE_PREFIX_PATH=<destdir>/usr/local` (and `SLIC3R_STATIC=1` on Unix).
**Note:** wxWidgets hardcodes the `destdir` path into `wx-config` on Unix, so the
dependency prefix cannot be relocated without reinstalling wxWidgets.

---

## 5. Vendored / bundled libraries inside `src/`

Added directly with `add_subdirectory()` from `src/CMakeLists.txt`:

`build-utils`, `admesh`, `boost` (nowide), `clipper`, `clipper2`, `miniz`, `minilzo`,
`glu-libtess`, `qhull`, `Shiny`, `semver`, `libigl`, `hints`, `mcut`, `libnest2d`,
and (GUI builds) `imgui`, `imguizmo`, `hidapi`.

Additional vendored sources present under `src/`: `agg`, `ankerl`, `eigen`,
`fast_float`, `nanosvg`, `nlohmann` (JSON), `stb_dxt`, `tinybvh`.

---

## 6. Embedded device web UI (`DeviceWeb/device_page`)

Package manager: **pnpm 10.12.1**. Runtime dependencies (`package.json`):

| Package | Version | Purpose |
|---|---|---|
| react / react-dom | ^19.1.0 | UI framework |
| @tanstack/react-router | ^1.120.15 | Routing |
| zustand | ^5.0.6 | State management |
| immer | ^10.1.1 | Immutable state helpers |
| i18next / react-i18next | ^25.3.2 / ^15.6.1 | Localization |
| @radix-ui/react-dialog, -popover, -toggle-group, -icons; radix-ui | ^1.1.x | Accessible UI primitives |
| tailwindcss / @tailwindcss/vite | ^4.1.8 | Styling |

Dev/test dependencies:

| Package | Version | Purpose |
|---|---|---|
| vite / @vitejs/plugin-react | ^6.3.5 / ^4.4.1 | Build tooling |
| typescript | ~5.8.3 | Typed JS |
| @playwright/test | ^1.60.0 | E2E testing |
| eslint / typescript-eslint / @eslint/js | ^9.25.0 / ^8.30.1 | Linting |
| eslint-plugin-compat, -react-hooks, -react-refresh, globals | — | Lint rules |
| i18next-parser | ^9.4.0 | Extract translation keys |
| lightningcss / postcss / terser | pinned/^ | CSS/JS optimization |
| @tanstack/router-plugin | ^1.120.15 | Route generation |
| @types/react(-dom) | ^19.1.x | React typings |

Browser targets: Chrome ≥109, Edge ≥109, Safari ≥13.1.

Other web assets: `resources/web/` (guide, shared include) and `tests/web-e2e/`
(Playwright tests for the app-level web UI).

---

## 7. Testing requirements

| Framework | Version / source | Notes |
|---|---|---|
| Catch2 | bundled v2 (`tests/catch2/catch.hpp`) | C++ tests; suites in `tests/`; `CATCH_EXTRA_ARGS` cache var. Some suites are `EXCLUDE_FROM_ALL` (stale after fork). |
| Perl modules | via `Build.PL` | `Devel::CheckLib`, `ExtUtils::MakeMaker ≥6.80`, `ExtUtils::ParseXS ≥3.22`, `ExtUtils::XSpp`, `ExtUtils::CppGuess`, `ExtUtils::Typemaps`, `Module::Build::WithXSpp ≥0.14`, `Moo`, `Test::More`, `IO::Scalar`, `Time::HiRes`, `Scalar::Util`, etc. Recommended: `Class::XSAccessor`, `Test::Harness`. Only needed for XS/Perl tests. |
| Playwright | ^1.60.0 | Web e2e; browsers installed separately (`npx playwright install`). |

---

## 8. Platform-specific requirements

- **Windows 64-bit:** MSVC (VS 2022/2026 generators in presets), WebView2 runtime,
  `ws2_32`, `uxtheme`, `Setupapi`, `user32`, `oleacc`; optional ARM64/ARM64EC deps bundle.
- **macOS 64-bit:** Clang, Xcode frameworks (Cocoa, AVFoundation, AVKit, CoreMedia,
  VideoToolbox, IOKit, CoreFoundation, OpenGL), `iconv`, `libc++`; wxWidgets via frameworks.
- **Linux:** GCC/Clang, GTK2/3 (wxWidgets), OpenGL/X11 dev packages, `libdbus-1`,
  `pangoft2`, `iconv`, threads; AppImage tooling for `-i`; Flatpak/native Debian packaging
  available. PrusaSlicer's Linux build guide is the reference.

---

## 9. Runtime data requirements

The application expects `resources/` alongside the binary/executable, notably:

- `resources/profiles/` and `profiles_template/` — machine/process/filament presets (JSON).
- `resources/printers/`, `model/`, `calib/`, `flush/`, `filament_mixing/` — printer and process data.
- `resources/shaders/` — OpenGL shaders.
- `resources/i18n/`, `resources/web/`, `resources/fonts/`, `resources/images/`,
  `resources/hms/`, `resources/dailytip/`, `resources/cert/` — UI, translations and assets.
- `BambuStudio.mo` — compiled message catalog; `bbl/i18n/` — translation sources
  (`BambuStudio.pot` + ~24 locale `.po` files); `localazy.json` — translation service config.

---

## 10. License note

BambuStudio, PrusaSlicer and Slic3r are **AGPL-3.0**. AGPL obligations apply even
when the software is used behind a web server. The optional Bambu networking plugin
is based on non-free libraries; without it, printing is done via SD card after slicing.
