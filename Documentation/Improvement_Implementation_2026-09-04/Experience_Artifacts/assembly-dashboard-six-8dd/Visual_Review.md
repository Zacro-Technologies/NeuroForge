# Installed coordinate and cube-net visual review — 2026-09-05

Source bundle: `/tmp/nf-assembly-dashboard-six-installed-20260905.xcresult`. Selected original attachments, the complete attachment manifest, exact selected-file SHA256 hashes, test outcomes and public-givens checks are retained beside this report. The complete223MB export including full activity trees remains at `/tmp/nf-installed-six-visual-review-20260905/`; this repository directory retains the bounded reviewed evidence subset. This was read-only inspection of an already completed run; no application, test or project file changed and no build was run.

The device recorded in this bundle is **iPhone SE (3rd generation), iOS Simulator 26.5 (23F77)**, device UUID `064C7C8F-D941-4D8C-9B55-958F4123AF02`. Inspected screenshots are 750 × 1334 pixels (375 × 667 points at 2×).

## Coordinate: label repair and geometry are visible

Test `testAdvancedCoordinatePublicLaunchSavesOriginalAnswerAndSeparateWorkedMap()` **passed**, 175.8523709774 s. It covers the public Coordinate Rotation secondary launch; this instance is an inverse-point question, not affine-inference or fixed-locus coverage.

[Worked coordinate screenshot](attachments/66F16311-6B4B-440F-892B-A93DF7DBA467.png)

- **C1 no longer overlaps the x-axis tick 1.** The orange center is at the origin; C1 appears below/right of it, distinctly below the axis numerals. The old apparent “C11” reading is absent in this capture.
- The entire drawn grid (−6…6), both labeled axes with grid units, P, Q and the origin marker are visible. The plot is above the fixed Next footer with clear room around its bounds; no coordinate point or axis label is cut off.
- P is visibly at (−3, 2), Q at (−2, −3). This matches the exported public givens: Q = (−2, −3), an active 90° counterclockwise rotation about (0, 0). Independently inverting that public operation yields P = (−3, 2).
- The separate [feedback screenshot](attachments/E4C4EE9C-AC73-4D26-B6E8-A5EAE2AA8D1F.png) shows the retained x = −3 and y = 2 in labeled fields, plus **Correct / 100% task credit**. This is independent confirmation of the visible numeric answer, not a claim that every later task kind was exercised.
- **Capture limitation:** the worked paragraph starts below the graph, but its final affine-map line is partially hidden behind the fixed footer in the worked screenshot. The feedback image also clips the lower explanation. These images do not prove full prose visibility; they do prove full graph visibility. They alone do not establish that the prose is unreachable by further scrolling.

The public oracle text is [060BF42A…txt](attachments/060BF42A-8C80-493E-883C-66F51AE7E947.txt). This passing case does not export a complete contemporaneous AX hierarchy; do not label the coordinate image as a full AX-tree audit.

## Cube-net: actual completed geometry captured; method still failed later

Test `testCubeNetRetainsPrintedGivensAcrossCameraAndCommittedFolding()` **failed**, 208.2312639952 s. The failure is later, at the selected-choice check after complete/unfold/restore: the lazy offscreen `No — at least one rule fails` button was absent from the query. The completed-model attachments are useful evidence of the reached states, but **the whole method and its final Next transition did not pass**.

[Completed native cube model](attachments/3A505934-6300-486C-AD4F-69C359357A10.png)

- This image genuinely contains a closed native 3D cube, not just worked prose. A is on the visible front face, B on the upper face, and C on the right face. Their printed arrows are drawn on the corresponding faces.
- The +y axis extends upward; +x extends down/right; +z extends down/left. The visible face assignment agrees with the public fixed anchor and the independently derived normals: A = +z, B = +y, C = +x. A's arrow follows +y; B/C arrows follow −z.
- The cube, visible labels/arrows, and all three axis labels are inside the viewport and above the footer. The geometry is roughly in the central y = 495…830 pixel span; the fixed footer begins around y = 1185. There is no geometry clipping in this screenshot.
- Visible face labels are small and perspective-compressed, especially C. The image proves their presence and location; it does not certify text sizing or all six face labels simultaneously. Back faces are naturally occluded. The separate accessible completed-frame text supplies all six exact normals and arrows.
- The Camera view / Authored view and Reset view controls are visible below the model. The next camera-description paragraph is partially hidden by the footer in this image; full paragraph visibility is not claimed.

[Completed six-face text](attachments/651EDF0E-A56B-4EC2-BA36-82C60986134C.png)

The entire completed-frame paragraph and its physical relation explanation are visible above the footer in this second image. It gives:

| Face | Outward normal | Printed arrow |
|---|---|---|
| A | (0, 0, 1) | (0, 1, 0) |
| B | (0, 1, 0) | (0, 0, −1) |
| C | (1, 0, 0) | (0, 0, −1) |
| D | (0, 0, −1) | (−1, 0, 0) |
| E | (−1, 0, 0) | (0, 0, 1) |
| F | (0, −1, 0) | (0, 0, 1) |

A separate pure check, using only the exported public square coordinates and the given fixed anchor, propagates the physical 90° hinge frames and matches all six rows exactly. The question requires BOTH “C and A are opposite” and “C arrow is −z”; the first is false and the second true, so the complete response is **No — at least one rule fails**. See [Public_Givens_Check.json](Public_Givens_Check.json), its reproducible [check_public_givens.py](check_public_givens.py), and the exported [public oracle](attachments/0AFEE0D5-6289-4E6F-8BB8-D3D1EC2584FF.txt). No app scorer or private answer source was called for that check.

AX evidence retained in `46A79B87-B925-4FD1-8A31-95F9A1CE4667.txt` and `3CE77AF0-9344-4F22-A133-E135ADD2A951.txt` identifies `net-folding-model` as **Image / Net model**, 327 × 300 points, plus the exact unchanged printed givens and the named camera controls. Those hierarchy dumps are from a later scroll position: the model frame is offscreen at y = −245.5 points. They establish identity/size, not simultaneous visibility in the completed-model screenshot. The visible screenshot is the direct geometry-visibility evidence. `Cube_Worked_AX_Snapshot_Strings.json` preserves the exact completed text found in the exported UIKit accessibility snapshots; it matches the visible table.

## Run outcome boundaries

| Method | Recorded result |
|---|---|
| Advanced coordinate public launch | Passed |
| Asymmetric solid public launch | Failed before launch at secondary-button reveal |
| Cube-net commitment/folding | Failed later at lazy selected-choice lookup |
| Feasible reconstruction public launch | Failed before launch at secondary-button reveal |
| Generated set separate runs/cold restore | Passed |
| Weekly chart exact answer history | Passed |

The two assembly tests did not reach their new geometry. Main-tree helper corrections reported by root are outside this already compiled bundle and have no execution result here.

An exported `.ips` attached under the cube case is the simultaneous **macOS** test-host stack failure: incident `744B6F62-CBF9-4C61-9745-C563E46A7F05`, process path ending `/NeuroForge.app/Contents/MacOS/NeuroForge`, with macOS 27.0 and `spatialDraft → makeDraft → ...prelaunch.preview`. It must not be misclassified as a simulator cube-rendering crash. The compact attribution is preserved in `Collated_Mac_Crash_Note.json`.
