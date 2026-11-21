# AGENTS.md — BambuStudio contributor / agent guide

> This file is the fast onboarding reference for developers and coding agents working in
> this repository. For the complete, categorized list of libraries, versions and platform
> requirements, see [`doc/DEPENDENCIES.md`](doc/DEPENDENCIES.md).

---

## 1. What is this project?

**BambuStudio** is a desktop 3D-printing slicer: it imports 3D models, lets the user
configure print parameters (material, nozzle, layer height, supports, infill, etc.),
slices the models into toolpaths, emits G-code, and sends the job to a 3D printer
(over the network or via SD card). It is a fork of **PrusaSlicer**, which is a fork of
**Slic3r**, and is licensed under **AGPL-3.0**.

Key facts:

| Item | Value |
|---|---|
| Application name / key | `BambuStudio` |
| Current version | `02.09.01.70` (`version.inc`; generated from git tags by build scripts) |
| License | GNU AGPL v3 (networking plugin is optional and partly non-free) |
| Primary language | C++17 |
| Build system | CMake ≥ 3.13 (CMakePresets require ≥ 3.20) |
| Main platforms | Windows 64-bit, macOS 64-bit, Linux (AppImage / Flatpak / native packages) |
| Upstream lineage | Slic3r → PrusaSlicer → BambuStudio |

Main features (from `README.md`): slicing + G-code viewer, multiple plates, remote
control/monitoring, auto-arrange/orient, tree/normal/custom supports, multi-material
printing and painting, global/object/part-level parameters, STEP import, assembly &
explosion view, flush/purge handling, and optional network printing via a plugin.

---

## 2. Read these files first

When starting a task, orient yourself with this short list:

| File | Why |
|---|---|
| `README.md` | Product overview, features, build/issue/license pointers. |
| `version.inc` | Version string and release flags (`BBL_RELEASE_TO_PUBLIC`, `BBL_INTERNAL_TESTING`). |
| `CMakeLists.txt` | Top-level options (`SLIC3R_GUI`, `SLIC3R_STATIC`, `SLIC3R_BUILD_TESTS`, …), dependency discovery, target graph. |
| `src/CMakeLists.txt` | Which bundled/vendored libraries are compiled and how the GUI target is assembled. |
| `src/libslic3r/CMakeLists.txt` | Core engine sources, CGAL/OpenCV/CASCADE linkage. |
| `src/slic3r/GUI/CMakeLists.txt` | GUI sources and embedded web UI integration. |
| `doc/DEPENDENCIES.md` | Full dependency/requirement inventory. |
| `doc/How to build - *.md` | Platform build notes (the Linux doc defers to PrusaSlicer's guide). |

---

## 3. Repository layout (directory map)

```
.
├── src/                     All C++ application code (engine + GUI + vendored libs)
│   ├── BambuStudio.cpp      Main entry point; CLI arg parsing; GUI_Run / headless modes
│   ├── libslic3r/           THE slicing engine (no GUI dependency) — see §4.1
│   ├── slic3r/              GUI layer and helpers — see §4.2
│   │   ├── GUI/             wxWidgets desktop application — see §4.2
│   │   │   └── DeviceWeb/   Embedded React/TypeScript web UI — see §4.3
│   │   ├── Config/          Config parsing helpers
│   │   └── Utils/           Misc. utilities
│   ├── platform/            OS-specific code: msw/, osx/, unix/
│   └── <vendored libs>/     admesh, agg, clipper, clipper2, eigen, imgui, imguizmo,
│                            libigl, libnest2d, miniz, minilzo, nanosvg, qhull,
│                            stb_dxt, tinybvh, Shiny, glu-libtess, semver, mcut, …  (see §5)
├── deps/                    ExternalProject scripts that download & build third-party deps
│                            (Boost, CGAL, wxWidgets, OCCT, OpenCV, TBB, OpenSSL, …).
│                            Platform variants: deps-linux/macos/windows/mingw/unix-common.cmake
├── xs/                      Perl XS / XSpp bindings exposing libslic3r to Perl (CLI/tests)
├── tests/                   C++ unit/integration tests (Catch2) + web e2e — see §6
├── resources/               Runtime data shipped with the app — see §4.5
├── bbl/                     Bambu-specific data & tooling (i18n catalogs under bbl/i18n/)
├── sandboxes/               Standalone C++ experiments/benchmarks (not part of the app)
├── cmake/                   CMake Find modules and MSVC helper scripts
├── scripts/                 Python maintenance scripts (e.g. check_profiles.py) + git hooks
├── packaging/               Debian/Ubuntu and other distro packaging metadata
├── docker/                  Dockerfile / Containerfile support files
├── .github/workflows/        CI: build_all, build_bambu, build_deps, cache checks, Homebrew, winget
├── doc/                     Build guides, localization guide, release notes, DEPENDENCIES.md
├── CMakeLists.txt           Root build definition
├── CMakePresets.json        Windows MSVC configure presets (debug/release, public/internal)
├── BuildLinux.sh / BuildMac.sh / BuildFedora.sh / build_win.bat / Build.PL / Docker*.sh
├── BambuStudio.mo           Compiled gettext message catalog
└── localazy.json            Translation-service (Localazy) configuration
```

---

## 4. Subsystem details

### 4.1 Core slicing engine — `src/libslic3r/`

Pure C++17 library (`libslic3r`), independent of the GUI. This is where almost all
"what happens to a model" logic lives. Namespaces are `Slic3r`.

| Area | Representative files | Responsibility |
|---|---|---|
| Model & geometry | `Model.{cpp,hpp}`, `TriangleMesh.{cpp,hpp}`, `Point`, `Polygon`, `Line`, `ExPolygon`, `BoundingBox`, `Geometry`, `CSGMesh/`, `AABBMesh`, `SurfaceMesh` | Object hierarchy, mesh representation, boolean ops, geometric primitives. |
| File formats | `Format/`, `TriangleMesh.cpp`, `SVG`, `NSVGUtils` | STL/OBJ/AMF/3MF/STEP import/export (STEP via OpenCASCADE in `MeshBooleanOpenMeshCraft`/CASCADE linkage). |
| Configuration | `Config`, `PrintConfig`, `Preset`, `PresetBundle`, `AppConfig`, `ParameterUtils` | Parameter definitions, validation, preset bundles, app settings. Generated config code lives alongside. |
| Print pipeline | `Print`, `PrintBase`, `PrintObject`, `PrintObjectSlice`, `PrintRegion`, `Layer`, `LayerRegion`, `Slicing`, `SlicingAdaptive` | Converts a `Model` into layered print objects and slicing regions. |
| Toolpath generation | `Fill/`, `PerimeterGenerator`, `BridgeDetector`, `Support/`, `Brim`, `GCode`, `GCodeWriter`, `GCodeReader`, `ExtrusionEntity*`, `Flow`, `CustomGCode` | Infill, perimeters, supports, brims, extrusion paths, G-code emission/parsing. |
| Specialized algorithms | `Arachne/`, `Fill/`, `Optimize/`, `Execution/`, `Interlocking/`, `TextureToColor/`, `SLA/`, `Geometry/`, `Shape/` | Arc-fitting/variable-width, light-weight perimetering, optimization, parallel execution, color decomposition, resin (SLA) printing. |
| Utilities | `I18N.hpp` (`_()` translation macro), `Log`, `Semver`, `Zipper`, `PNGReadWrite`, `Color`, `FileParserError` | Logging, translations, versioning, archives, images, colors. |

Notes when editing:
- Prefer keeping GUI-free code in `libslic3r`; geometry/algorithm work should not depend on wxWidgets.
- Compiled with `-DUSE_TBB` (TBB parallel execution utilities under `Execution/`).
- CGAL-backed boolean/mesh code is isolated in `libslic3r_cgal` (see `src/libslic3r/CMakeLists.txt`).

### 4.2 Desktop GUI — `src/slic3r/` and `src/slic3r/GUI/`

C++17 + **wxWidgets** (base, core, adv, html, gl, aui, net, media, webview, richtext,
xml), **OpenGL**, and **ImGui** (`imgui/`, `imguizmo/`) for overlays/gizmos.

| Area | Representative files | Responsibility |
|---|---|---|
| App bootstrap | `GUI/GUI_App.{cpp,hpp}`, `GUI/GUI_Init`, `MainFrame`, `BambuStudio.cpp` | Application object, startup, main window, command-line handling. |
| 3D viewport | `GUI/GLCanvas3D`, `3DScene`, `Camera`, `GLModel`, `GLShader`, `GCodeViewer`, `GCodeRenderer/`, `Gizmos/` | 3D scene rendering, camera, shaders, toolpath/G-code preview, manipulation gizmos. |
| Plater / plates | `GUI/Plater`, `PartPlate`, `GUI_ObjectList`, `Selection`, `2DBed`, `3DBed` | Project/plate management, object list, selection, bed rendering. |
| Slicing workflow | `GUI/BackgroundSlicingProcess`, `GUI_Preview`, `SliceInfoPanel` | Asynchronous slicing and preview tabs. |
| Presets & parameters | `GUI/ParamsPanel`, `GUI_ObjectSettings`, `PresetComboBoxes`, `Field`, `ConfigManipulation`, `Tab`, `Notebook` | UI for global/object/part settings and presets. |
| Printing / devices | `GUI/SendToPrinter`, `DeviceManager`, `Monitor*`, `ConnectPrinter`, `Printer/`, `DeviceTab/`, `DeviceCore/`, `QueuePrintController`, `HttpServer` | Printer discovery, send/monitor jobs, MQTT/network device features. |
| AMS / filaments | `GUI/AMS*`, `Filament*`, `AMSMaterialsSetting`, `AmsMappingPopup` | Automated Material System, filament mapping/mixing UI. |
| Dialogs & widgets | `GUI/*Dialog.*`, `Widgets/`, `UIHelpers/`, ` wxExtensions`, `BBLStatusBar*`, `dark_mode/` | Reusable widgets, status bars, theming. |
| Jobs / threading | `GUI/Jobs/` | Background jobs (slicing, mesh repair, uploads, etc.). |
| Localization | `GUI/I18N.{cpp,hpp}`, `resources/i18n/`, `bbl/i18n/` | wxWidgets translatable strings; gettext catalogs. |

Notes when editing:
- GUI symbols live in namespace `Slic3r::GUI`.
- Prefer putting reusable logic in `libslic3r` and thin UI adapters in `GUI/`.
- Long-running work belongs in `GUI/Jobs/` or `BackgroundSlicingProcess`, not on the UI thread.

### 4.3 Embedded device web UI — `src/slic3r/GUI/DeviceWeb/device_page/`

A separate **TypeScript + React 19** single-page app served inside the desktop app
(via wxWidgets `webview`/WebView2/CEF). Built with **Vite 6**, **Tailwind 4**,
**TanStack Router**, **Zustand**, **Radix UI**, and **i18next**. Package manager:
**pnpm**. It is wired into the CMake build via the `device_page_build` target
(`src/CMakeLists.txt`).

```
DeviceWeb/device_page/
├── src/
│   ├── routes/          TanStack Router route components (device_page/*, filament_manager, about, …)
│   ├── components/      Reusable React components (ImageButton, ProgressBar, ScrollView, …)
│   ├── store/           Zustand slices (DeviceSlice, AmsSlice, FilamentSlice, SlotSlice, AppStore, …)
│   ├── utils/           Helpers, dialogs, resize listeners, SVG canvas
│   └── i18n.tsx         i18next setup
├── tests/e2e/           Playwright end-to-end specs
├── tools/               Build helper scripts (e.g. check-legacy-css.mjs)
├── package.json         Dependencies/scripts (`dev`, `build`, `lint`, `e2e`, `i18n`)
└── tsconfig / vite config
```

Commands (run from `src/slic3r/GUI/DeviceWeb/device_page/`):
`pnpm install`, `pnpm dev`, `pnpm build`, `pnpm lint`, `pnpm e2e`, `pnpm i18n`.

### 4.4 CLI / Perl bindings — `xs/`

Perl XS/XSpp bindings (`main.xs.in`, `xsp/*.xsp`, `src/perlglue.cpp`, `lib/Slic3r/XS.pm`)
expose a subset of `libslic3r` to Perl. Used by legacy command-line tooling and the
`xs/t/*.t` regression tests (`perl Build.PL` installs the needed Perl modules;
`prove -l xs/t`). This layer is not required to build/run the GUI.

### 4.5 Runtime data — `resources/`

Data shipped with the application and consulted at runtime:

| Path | Contents |
|---|---|
| `resources/profiles/`, `profiles_template/` | Machine/process/filament print presets (JSON). |
| `resources/printers/`, `model/`, `calib/`, `flush/`, `filament_mixing/` | Printer definitions, model configs, calibration and flushing data. |
| `resources/i18n/` | gettext translations used by the app. |
| `resources/shaders/` | OpenGL shaders for the 3D viewport. |
| `resources/fonts/`, `images/`, `icons` (Icon.icns), `cert/`, `web/` | UI assets, web guide assets, certificates. |
| `resources/hms/`, `dailytip/`, `info/`, `tooltip/` | Help messages, tips, tooltips. |

Do not edit generated/user profiles blindly — check `scripts/check_profiles.py` first.

### 4.6 Tests — `tests/`

- C++ tests use a bundled **Catch2 v2** (`tests/catch2/catch.hpp`, `catch_main.hpp`).
- `tests/CMakeLists.txt` defines `test_common` / `test_gui` interface targets and adds suites:
  `slic3rutils`, `fff_print`, `fila_manager`, `filament_group`, `nozzle_inventory`,
  `libslic3r_utils`, `material_color_label`, plus `EXCLUDE_FROM_ALL` suites
  (`libnest2d`, `libslic3r`, `sla_print`, `cpp17`) that are stale after the fork.
- Test fixtures live in `tests/data/`.
- Web e2e tests live in `tests/web-e2e/` and the device page's `tests/e2e/` (Playwright).

### 4.7 Supporting directories

- `deps/` — CMake `ExternalProject` download/build recipes for all third-party libraries;
  output installs into a `destdir` used as `CMAKE_PREFIX_PATH` (unix needs `SLIC3R_STATIC=1`).
- `cmake/modules/` — custom `Find*.cmake` modules; `cmake/msvc/` — MSVC helpers.
- `sandboxes/` — non-shipping experiments (`aabb-evaluation`, `meshboolean`, `opencsg`,
  `openvdb`, `slasupporttree`, …), useful for isolating algorithm work.
- `packaging/` — native Debian/Ubuntu packaging; `docker/` — container support.
- `.github/workflows/` — CI for dependencies, full builds, cache validation, Homebrew and winget.
- `bbl/i18n/` — translation catalogs (`BambuStudio.pot` + ~24 locale `.po` files).
- `scripts/hooks/` — git hooks; `localazy.json` — translation service config.

---

## 5. Languages & frameworks summary

| Layer | Language / framework |
|---|---|
| Slicing engine & desktop app | C++17 (`.clang-format` uses `Cpp11`-based style) |
| GUI toolkit | wxWidgets 3.0/3.1, OpenGL, GLEW, GLFW, ImGui/ImGuizmo |
| Embedded device UI | TypeScript, React 19, Vite 6, Tailwind CSS 4, Zustand, TanStack Router, Radix UI, i18next |
| CLI / legacy bindings | Perl, XS, XSpp |
| Build | CMake, Ninja/Visual Studio/Make, CMakePresets, shell/batch build scripts, Docker |
| Tests | Catch2 (C++), Perl `prove`, Playwright (web) |
| i18n | gettext (`.po`/`.pot`), i18next for the web UI |

---

## 6. Build & test quick reference

### 6.1 Dependencies first

```bash
# Linux (per BuildLinux.sh usage): install/update deps, then build deps + app + AppImage
sudo ./BuildLinux.sh -u
./BuildLinux.sh -dsi
```

The `deps/` project downloads and installs third-party libraries into a `destdir`;
point the main build at it with `-DCMAKE_PREFIX_PATH=<destdir>/usr/local` and
`-DSLIC3R_STATIC=1` on Unix.

### 6.2 Main CMake build

```bash
cmake -S . -B build \
  -DSLIC3R_GUI=ON \
  -DSLIC3R_STATIC=1 \
  -DSLIC3R_BUILD_TESTS=ON \
  -DCMAKE_PREFIX_PATH=/path/to/deps/destdir/usr/local
cmake --build build --config Release -j
```

Windows presets: `cmake --preset msvc_release` / `msvc_debug` (and `*_public`
variants that set `BBL_RELEASE_TO_PUBLIC=1`). Other flags: `SLIC3R_GTK` (wx GTK
version, default `2`), `BBL_INTERNAL_TESTING`, `SLIC3R_ENABLE_OPENMESHCRAFT_BOOLEAN`,
`SLIC3R_ALLOW_MCUT_BOOLEAN`.

### 6.3 Tests

```bash
ctest --test-dir build --output-on-failure            # C++ (if SLIC3R_BUILD_TESTS=ON)
perl Build.PL && prove -l xs/t                        # Perl XS tests
cd src/slic3r/GUI/DeviceWeb/device_page && pnpm e2e   # Web e2e (Playwright)
```

---

## 7. Conventions & "where do I change X?"

- **C++ standard:** C++17; formatting via `.clang-format` (`Cpp11` base, project-specific overrides).
- **Namespaces:** `Slic3r` for engine, `Slic3r::GUI` for GUI.
- **File pairs:** implementation in `*.cpp`, headers in `*.hpp` (some legacy `*.h`).
- **New slicing/geometry logic:** `src/libslic3r/` (+ a test in the matching `tests/` suite).
- **New UI:** `src/slic3r/GUI/`; long work → `GUI/Jobs/`; new device page route → `DeviceWeb/device_page/src/routes/` + a Zustand slice if state is needed.
- **New print parameter:** `PrintConfig`/`Config` definitions, then `GUI/ParamsPanel`/`Field` UI, then preset JSON in `resources/profiles*`; run `scripts/check_profiles.py`.
- **Strings:** wrap with the translation macro `_()` (engine) / wx translation in GUI; web UI uses i18next (`pnpm i18n` regenerates catalogs); update `bbl/i18n`/`resources/i18n` catalogs.
- **Keep engine GUI-free, keep GUI thin:** algorithms in `libslic3r`, adapters in GUI.
- **Never commit generated artifacts** (see `.gitignore`): `build/`, compiled `.mo`, vendored downloads, `node_modules`, etc.

## 8. Deep dive

For the full, categorized dependency and requirement inventory (versions, vendored
libraries, platform-specific packages/frameworks, web UI packages, tooling), read
[`doc/DEPENDENCIES.md`](doc/DEPENDENCIES.md).
