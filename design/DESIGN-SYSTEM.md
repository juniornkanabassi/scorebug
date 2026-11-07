# Native control panel

The app keeps the existing sidebar window, with Primary, Secondary and Team Library as destinations. Settings opens in the system Settings scene. The broadcast overlay has its own design and is outside these tokens.

## Spacing and layout

`Sources/Scorebug/UI/Grid.swift` defines the 4 pt scale. Use `Space.sm` between related controls, `Space.md` for compact groups and `Space.lg` inside match panels. `Space.margin` is the normal page margin. Use `gridArea` and `gridProbe` on custom panels; system Forms and Lists manage their own alignment. Run `tools/grid-lint.sh` and the snapshot layout checks after changes.

Keep the existing large live scores and minimum 44 pt match controls. They are deliberate requirements for operating a stream, including at enlarged text sizes. Preview dimensions follow the broadcast aspect ratios and are not spacing values.

## Colour

`UI/Surfaces.swift` owns native surface and status colours, plus competition fallback colours. Use system semantic backgrounds and labels. Match panels use `controlBackgroundColor`, a separator stroke and primary-colour sentence-case headings. Status includes a word or symbol as well as colour. Dynamic club colours remain user data, not app chrome.

For a competition fallback fill, use `Surface.text(on:)`. It chooses the higher-contrast black or white foreground using WCAG relative luminance. Do not assume white text works on orange or gold. The opaque preview canvas and imported mark backing are intentional exceptions with named tokens.

## Corners and type

`UI/Radius.swift` owns small, medium and large radii. Use system shapes for capsules and circles. Keep the existing `scaledFont` and `scaledControl` helpers so text zoom continues to enlarge controls. Small competition marks are colour shapes with accessible names, not tiny initials.

## Commands and settings

Match commands use the focused scene's actions. Goal commands use the same scorer prompt as the plus buttons. Reset opens the existing confirmation. Settings has OBS, Live Data and Advanced tabs, retains every previous option, and remembers the selected tab. Each main window pins its own SceneStorage destination on appearance; the last pick is also stored explicitly to survive disabled window restoration. Error alert titles name the failed task and retain the original diagnostic.

## Verification

`Scripts/native-style-check.sh` covers contrast, selection decoding and error titles. `Scripts/native-snapshots.sh <binary>` renders every page and each Settings tab in light and dark without showing a window, plus both match pages at zoom level 2 and all five real operating panels at the maximum zoom level 3 (1.7×). It uses only disposable fixtures under `/private/tmp/bama/build-scorebug`.

The offscreen renderer checks content layout, not active window chrome or a live WebKit preview. Verify those with a live window before release. The existing overlay acceptance captures remain the proof for broadcast pixels.
