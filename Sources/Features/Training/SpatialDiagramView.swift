import SwiftUI
import RealityKit

#if os(macOS)
import AppKit
private typealias NFSpatialPlatformColor = NSColor
private extension NSColor {
    static var nfSpatialLabel: NSColor { .labelColor }
}
#else
import UIKit
private typealias NFSpatialPlatformColor = UIColor
private extension UIColor {
    static var nfSpatialLabel: UIColor { .label }
}
#endif

/// A code-native stimulus renderer used by every spatial exercise. Three-
/// dimensional stimuli use real RealityKit geometry and always retain an
/// explicitly selectable static 2D equivalent. No scene animates automatically.
/// The retained description preserves original givens. It is not a validated
/// substitute for a visual assessment; rendering never determines scoring.
struct NFSpatialDiagramView: View {
    private enum Presentation: String, CaseIterable, Identifiable {
        case nativeThreeDimensional = "Native 3D"
        case staticTwoDimensional = "Static 2D"

        var id: String { rawValue }
    }

    let metadata: NFSpatialRepresentationMetadata
    let localeIdentifier: String
    let prefersReducedMotion: Bool
    let exercise: NFExercise?
    let learningPhase: NFSpatialLearningPhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var presentation: Presentation = .nativeThreeDimensional
    @State private var cameraView = "Authored view"
    @State private var resetGeneration = 0
    @State private var objectCopy = NFSpatialObjectCopy.authored

    init(metadata: NFSpatialRepresentationMetadata, localeIdentifier: String, prefersReducedMotion: Bool = false,
         exercise: NFExercise? = nil, learningPhase: NFSpatialLearningPhase = .independent) {
        self.metadata = metadata
        self.localeIdentifier = localeIdentifier
        self.prefersReducedMotion = prefersReducedMotion
        self.exercise = exercise
        self.learningPhase = learningPhase
    }

    private var locale: Locale { Locale(identifier: localeIdentifier) }
    private var toolPolicy: NFSpatialToolPolicy { .resolve(exercise: exercise, metadata: metadata, phase: learningPhase) }
    private var displayedMetadata: NFSpatialRepresentationMetadata { objectCopy.metadata(from: metadata, policy: toolPolicy) }
    private var foldedCopy: Bool { toolPolicy.allowsObjectChanges && toolPolicy.kind == .cubeNet && objectCopy.isFolded }
    private var canRender: Bool {
        NFSpatialRenderingSafety.permits(metadata)
            && (!metadata.objectDescription.localizedCaseInsensitiveContains("cube net")
                || NFCubeNetEngine.displayFaces(encodedDescription: metadata.objectDescription) != nil)
    }

    private var reducesMotion: Bool {
        accessibilityReduceMotion || prefersReducedMotion
    }

    var body: some View {
        if metadata.stimulusCategory == "spatial-assembly-contract" {
            if let exercise,let value=NFSpatialAssemblyContract.make(exercise:exercise),value.representation == metadata {
                NFSpatialAssemblyStimulusView(contract:value,phase:learningPhase,prefersReducedMotion:reducesMotion)
            }else{Text("This saved spatial assembly needs a compatible version. Its original question and response remain saved.")}
        } else if metadata.stimulusCategory == "coordinate-reasoning-contract" {
            if let exercise,let value=NFCoordinateReasoningContract.make(exercise:exercise),value.representation == metadata {
                NFCoordinateReasoningStimulusView(contract:value,phase:learningPhase)
            } else {Text("This saved transformation reasoning task needs a compatible version. Its original question and response remain saved.")}
        } else if metadata.stimulusCategory == "cube-net-contract" {
            if let exercise,let value=NFNetFoldingContract.make(exercise:exercise),value.representation == metadata {
                NFNetFoldingStimulusView(contract:value,phase:learningPhase,prefersReducedMotion:reducesMotion)
            } else {Text("This saved cube-net task needs a compatible version. Its original question and response remain saved.")}
        } else if metadata.stimulusCategory.hasPrefix("solid-section-") {
            if let exercise,let value=NFSolidSectionContract.make(exercise:exercise),value.representation == metadata {
                NFSolidSectionStimulusView(contract:value,phase:learningPhase,prefersReducedMotion:reducesMotion)
            } else {
                Text("This saved solid section needs a compatible version. Its original question and response remain saved.")
            }
        } else if metadata.stimulusCategory.hasPrefix("coordinate-contract-") {
            if let exercise,let value=NFCoordinateTransformContract.make(exercise:exercise),value.representation == metadata {
                NFCoordinateTransformStimulusView(contract:value,phase:learningPhase)
            } else {
                Text("This saved coordinate transformation needs a compatible version. Its original question and response remain saved.")
            }
        } else if metadata.stimulusCategory.hasPrefix("structured-") {
            if let exercise, let contract = NFSpatialStructureContract.make(exercise: exercise), contract.representation == metadata {
                NFSpatialStructureStimulusView(contract: contract, phase: learningPhase, prefersReducedMotion: prefersReducedMotion)
            } else {
                Text("This saved spatial structure needs a compatible version. Its original question and response remain saved.")
            }
        } else { legacyBody }
    }
    private var legacyBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(metadata.dimension == .threeDimensional ? "3D model" : "2D diagram", systemImage: "move.3d")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(metadata.operations.map(\.title).joined(separator: " · "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            if !canRender {
                Label("This diagram cannot be rendered safely. Its original description is retained.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if metadata.dimension == .threeDimensional {
                Picker("Spatial rendering mode", selection: $presentation) {
                    ForEach(Presentation.allCases) { mode in
                        Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Switch between native three-dimensional geometry and a motion-free schematic. The original description remains available.")

                if presentation == .nativeThreeDimensional {
                    NFSpatialRealityView(
                        metadata: displayedMetadata,
                        foldedNet: foldedCopy,
                        permitsOrbit: !reducesMotion,
                        cameraView: cameraView
                    )
                    .id("\(cameraView)-\(resetGeneration)")
                    Text(reducesMotion
                         ? "Reduced Motion is active. The camera is fixed; Static 2D shows a motion-free schematic."
                         : "Drag the view to orbit the camera. The object and answer are unchanged; Static 2D remains available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    staticDiagram
                }
                if presentation == .nativeThreeDimensional || !metadata.points.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack { cameraControls }
                        VStack(alignment: .leading) { cameraControls }
                    }
                }
            } else {
                staticDiagram
            }

            LabeledContent("Task orientation", value: metadata.viewpoint)
            if canRender { objectControls }
            Text(metadata.accessibilityDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Diagram description: \(metadata.accessibilityDescription)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: metadata) { _, _ in objectCopy.reset(); cameraView = "Authored view"; resetGeneration += 1 }
        .onChange(of: learningPhase) { _, phase in
            if phase == .independent { objectCopy.reset() }
        }
        .animation(nil, value: objectCopy)
    }

    @ViewBuilder private var cameraControls: some View {
        Button("Reset view") {
            cameraView = "Authored view"; resetGeneration += 1
            AccessibilityNotification.Announcement(NFAppLocalization.localizedCatalogValue("Camera reset to the authored view. The object and answer are unchanged.", locale: locale)).post()
        }
            .frame(minHeight: 44)
        Picker("Camera view", selection: $cameraView) {
            Text("Authored view").tag("Authored view")
            Text("Front").tag("Front")
            Text("Side").tag("Side")
            Text("Top").tag("Top")
        }.pickerStyle(.menu)
        Text("Camera changes do not change your answer.").font(.footnote).foregroundStyle(.secondary)
    }


    @ViewBuilder private var objectControls: some View {
        if toolPolicy.kind != .unavailable {
            VStack(alignment: .leading, spacing: 10) {
                Label("Object copy tools", systemImage: "rotate.3d").font(.headline)
                Text("These tools change a demonstration copy. Camera movement and your saved answer stay separate.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !toolPolicy.allowsObjectChanges {
                    Text("Object tools open after saving your answer or revealing the worked solution. They are not available during independent answering.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("spatial-tools-restricted")
                }
                if toolPolicy.kind == .coordinates {
                    Text("Positive rotations are counterclockwise when viewed from the positive axis toward the origin.")
                        .font(.footnote).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                        ForEach(NFSpatialCopyOperation.available(for: metadata.dimension)) { operation in
                            Button {
                                guard objectCopy.apply(operation, policy: toolPolicy, metadata: metadata) else { return }
                                announce(operation.title(dimension: metadata.dimension, locale: locale))
                            } label: { Text(operation.title(dimension: metadata.dimension, locale: locale)).frame(maxWidth: .infinity, minHeight: 44) }
                                .buttonStyle(.bordered).disabled(!toolPolicy.allowsObjectChanges)
                                .accessibilityIdentifier("spatial-object-" + operation.rawValue)
                        }
                    }
                } else if toolPolicy.kind == .cubeNet {
                    ViewThatFits(in: .horizontal) {
                        HStack { foldingButtons }
                        VStack(alignment: .leading) { foldingButtons }
                    }
                    Text("Fold and Unfold show exact endpoint states without animation.").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Reset object") {
                    objectCopy.reset()
                    announce(NFAppLocalization.localizedCatalogValue("Object reset to the authored state.", locale: locale))
                }.buttonStyle(.bordered).frame(minHeight: 44).disabled(!toolPolicy.allowsObjectChanges)
                    .accessibilityIdentifier("spatial-reset-object")
                if let description = objectCopy.description(original: metadata, policy: toolPolicy, locale: locale) {
                    Text(description).textSelection(.enabled).accessibilityIdentifier("spatial-object-state")
                }
            }
        } else if exercise != nil {
            Text("Object manipulation is unavailable for this item. Use the retained diagram, dimensions and description; this schematic is not a validated alternative spatial assessment.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var foldingButtons: some View {
        Button("Fold object") {
            guard objectCopy.setFolded(true, policy: toolPolicy) else { return }
            announce(NFAppLocalization.localizedCatalogValue("The labeled net is folded into a cube.", locale: locale))
        }.buttonStyle(.bordered).frame(minHeight: 44).disabled(!toolPolicy.allowsObjectChanges || objectCopy.isFolded)
            .accessibilityIdentifier("spatial-fold-object")
        Button("Unfold object") {
            guard objectCopy.setFolded(false, policy: toolPolicy) else { return }
            announce(NFAppLocalization.localizedCatalogValue("The original labeled net is unfolded.", locale: locale))
        }.buttonStyle(.bordered).frame(minHeight: 44).disabled(!toolPolicy.allowsObjectChanges || !objectCopy.isFolded)
            .accessibilityIdentifier("spatial-unfold-object")
    }
    private func announce(_ action: String) {
        let state = objectCopy.description(original: metadata, policy: toolPolicy, locale: locale) ?? ""
        AccessibilityNotification.Announcement(action + " " + state).post()
    }

    private var staticDiagram: some View {
        Canvas { context, size in
            drawBackground(in: &context, size: size)
            if !metadata.points.isEmpty {
                drawCoordinateStimulus(in: &context, size: size)
            } else if metadata.objectDescription.localizedCaseInsensitiveContains("cube net") {
                if foldedCopy { drawFoldedCube(in: &context, size: size) }
                else { drawCubeNet(in: &context, size: size) }
            } else if metadata.operations.contains(.crossSection) {
                drawCrossSection(in: &context, size: size)
            } else {
                drawProjectedSolid(in: &context, size: size)
            }
        }
        .frame(minHeight: 230, idealHeight: 280)
        .accessibilityHidden(true)
    }

    private func drawBackground(in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
        context.fill(
            Path(roundedRect: bounds, cornerRadius: 14),
            with: .color(Color.primary.opacity(0.035))
        )
        var grid = Path()
        let spacing: CGFloat = 28
        var x: CGFloat = spacing
        while x < size.width {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y: CGFloat = spacing
        while y < size.height {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(grid, with: .color(Color.primary.opacity(0.055)), lineWidth: 1)
    }

    private func drawCoordinateStimulus(in context: inout GraphicsContext, size: CGSize) {
        let margin: CGFloat = 36
        let plot = CGRect(
            x: margin,
            y: margin,
            width: max(1, size.width - margin * 2),
            height: max(1, size.height - margin * 2)
        )
        let origin = CGPoint(x: plot.midX, y: plot.midY)
        var axes = Path()
        axes.move(to: CGPoint(x: plot.minX, y: origin.y))
        axes.addLine(to: CGPoint(x: plot.maxX, y: origin.y))
        axes.move(to: CGPoint(x: origin.x, y: plot.minY))
        axes.addLine(to: CGPoint(x: origin.x, y: plot.maxY))
        context.stroke(axes, with: .color(Color.primary.opacity(0.65)), lineWidth: 1.5)

        let projected = displayedMetadata.points.map { NFSpatialOrthographicProjection.components($0, camera: cameraView) }
        let maximumCoordinate = max(
            2,
            projected.flatMap { [abs($0.horizontal), abs($0.vertical)] }.max() ?? 2
        ) + 1
        let scale = min(plot.width, plot.height) / CGFloat(maximumCoordinate * 2)
        for point in displayedMetadata.points {
            let projected = NFSpatialOrthographicProjection.components(point, camera: cameraView)
            let location = CGPoint(
                x: origin.x + CGFloat(projected.horizontal) * scale,
                y: origin.y - CGFloat(projected.vertical) * scale
            )
            var vector = Path()
            vector.move(to: origin)
            vector.addLine(to: location)
            context.stroke(vector, with: .color(NFTheme.indigo.opacity(0.75)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: location.x - 6, y: location.y - 6, width: 12, height: 12)), with: .color(NFTheme.cyan))
            context.draw(
                Text("\(point.label)  (\(format(point.x)), \(format(point.y))\(point.z.map { ", \(format($0))" } ?? ""))")
                    .font(.caption.bold())
                    .foregroundColor(.primary),
                at: CGPoint(x: min(plot.maxX - 35, location.x + 38), y: max(plot.minY + 10, location.y - 16))
            )
        }
        let labels = NFSpatialOrthographicProjection.axisLabels(metadata: metadata, camera: cameraView)
        context.draw(Text(labels[0]).font(.caption), at: CGPoint(x: plot.maxX - 6, y: origin.y + 14))
        context.draw(Text(labels[1]).font(.caption), at: CGPoint(x: origin.x + 14, y: plot.minY + 6))
    }

    private func drawCubeNet(in context: inout GraphicsContext, size: CGSize) {
        guard NFCubeNetEngine.displayFaces(encodedDescription: metadata.objectDescription) != nil,
              let layout = NFCubeNetLayout(encodedDescription: metadata.objectDescription) else { return }
        let minimumX = layout.cells.map(\.x).min() ?? 0
        let maximumX = layout.cells.map(\.x).max() ?? 0
        let minimumY = layout.cells.map(\.y).min() ?? 0
        let maximumY = layout.cells.map(\.y).max() ?? 0
        let columns = CGFloat(maximumX - minimumX + 1)
        let rows = CGFloat(maximumY - minimumY + 1)
        let side = min(size.width / (columns + 1.4), size.height / (rows + 1.4))
        let origin = CGPoint(
            x: (size.width - columns * side) / 2,
            y: (size.height - rows * side) / 2
        )
        for face in layout.cells {
            let rect = CGRect(
                x: origin.x + CGFloat(face.x - minimumX) * side,
                y: origin.y + CGFloat(face.y - minimumY) * side,
                width: side,
                height: side
            )
            context.fill(Path(rect), with: .color(face.label == "A" ? NFTheme.indigo.opacity(0.22) : NFTheme.cyan.opacity(0.12)))
            context.stroke(Path(rect), with: .color(Color.primary.opacity(0.75)), lineWidth: 2)
            context.draw(Text(face.label).font(.headline), at: CGPoint(x: rect.midX, y: rect.midY))
        }
    }

    private func drawFoldedCube(in context: inout GraphicsContext, size: CGSize) {
        guard let faces = NFCubeNetEngine.displayFaces(encodedDescription: metadata.objectDescription) else { return }
        let scale = min(size.width, size.height) * 0.55
        func project(_ point: SIMD3<Double>) -> CGPoint {
            CGPoint(x: size.width / 2 + CGFloat(point.x - point.z) * scale * 0.75,
                y: size.height / 2 + CGFloat(-point.y + (point.x + point.z) * 0.38) * scale)
        }
        for face in faces where face.normal.x == 1 || face.normal.y == 1 || face.normal.z == 1 {
            func vector(_ value: SIMD3<Int32>) -> SIMD3<Double> { SIMD3(Double(value.x), Double(value.y), Double(value.z)) }
            let center = vector(face.normal) * 0.5, right = vector(face.right) * 0.5, up = vector(face.up) * 0.5
            let corners = [center - right - up, center + right - up, center + right + up, center - right + up]
            var outline = Path(); outline.addLines(corners.map { project($0) }); outline.closeSubpath()
            context.fill(outline, with: .color(NFTheme.indigo.opacity(face.normal.y == 1 ? 0.16 : 0.3)))
            context.stroke(outline, with: .color(Color.primary.opacity(0.7)), lineWidth: 2)
            context.draw(Text(face.label).font(.title3.bold()), at: project(center))
        }
    }

    private func drawCrossSection(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let width = min(size.width * 0.46, 260)
        let height = min(size.height * 0.56, 150)
        if metadata.objectDescription.localizedCaseInsensitiveContains("cube") {
            drawWireBox(in: &context, rect: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
        } else {
            let body = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
            context.stroke(Path(ellipseIn: body), with: .color(NFTheme.indigo), lineWidth: 3)
        }
        let plane = CGRect(x: center.x - width * 0.62, y: center.y - 18, width: width * 1.24, height: 36)
        context.fill(Path(roundedRect: plane, cornerRadius: 5), with: .color(NFTheme.amber.opacity(0.25)))
        context.stroke(Path(roundedRect: plane, cornerRadius: 5), with: .color(NFTheme.amber), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
        context.draw(Text("section plane").font(.caption.bold()), at: CGPoint(x: plane.midX, y: plane.minY - 12))
    }

    private func drawProjectedSolid(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(
            x: size.width * 0.24,
            y: size.height * 0.26,
            width: size.width * 0.46,
            height: size.height * 0.42
        )
        drawWireBox(in: &context, rect: rect)
        let arrowX = rect.maxX + 34
        var arrow = Path()
        arrow.move(to: CGPoint(x: arrowX, y: rect.maxY + 22))
        arrow.addLine(to: CGPoint(x: arrowX, y: rect.minY - 20))
        arrow.addLine(to: CGPoint(x: arrowX - 7, y: rect.minY - 10))
        arrow.move(to: CGPoint(x: arrowX, y: rect.minY - 20))
        arrow.addLine(to: CGPoint(x: arrowX + 7, y: rect.minY - 10))
        context.stroke(arrow, with: .color(NFTheme.cyan), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        context.draw(Text(metadata.viewpoint).font(.caption.bold()), at: CGPoint(x: size.width / 2, y: size.height - 20))
    }

    private func drawWireBox(in context: inout GraphicsContext, rect: CGRect) {
        let offset = CGPoint(x: rect.width * 0.18, y: -rect.height * 0.2)
        let back = rect.offsetBy(dx: offset.x, dy: offset.y)
        context.stroke(Path(rect), with: .color(NFTheme.indigo), lineWidth: 3)
        context.stroke(Path(back), with: .color(NFTheme.indigo.opacity(0.55)), lineWidth: 2)
        var connectors = Path()
        for (front, rear) in [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: back.minX, y: back.minY)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: back.maxX, y: back.minY)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: back.minX, y: back.maxY)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: back.maxX, y: back.maxY))
        ] {
            connectors.move(to: front)
            connectors.addLine(to: rear)
        }
        context.stroke(connectors, with: .color(NFTheme.indigo.opacity(0.75)), lineWidth: 2)
    }

    private func format(_ value: Double) -> String {
        NFSpatialRenderingSafety.coordinateLabel(value, locale: Locale(identifier: localeIdentifier))
    }
}

private struct NFSpatialRealityView: View {
    let metadata: NFSpatialRepresentationMetadata
    let foldedNet: Bool
    let permitsOrbit: Bool
    let cameraView: String

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let scene = NFSpatialRealitySceneFactory.makeScene(for: metadata, foldedNet: foldedNet)
            if cameraView == "Side" { scene.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 1, 0)) }
            if cameraView == "Top" { scene.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0)) }
            content.add(scene)
            content.cameraTarget = scene
        } update: { content in
            guard let scene = content.entities.first(where: { $0.name == NFSpatialRealitySceneFactory.rootEntityName }) else { return }
            NFSpatialRealitySceneFactory.updateObject(in: scene, metadata: metadata, foldedNet: foldedNet)
        } placeholder: {
            ProgressView("Preparing 3D model")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .realityViewCameraControls(permitsOrbit ? .orbit : .none)
        .frame(minHeight: 230, idealHeight: 280)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .accessibilityHidden(true)
    }
}

/// Kept separate from the SwiftUI view so deterministic generator tests can
/// verify that every 3D metadata family produces actual RealityKit geometry.
@MainActor
enum NFSpatialRealitySceneFactory {
    static let rootEntityName = "nf.spatial.scene"
    static let stimulusEntityName = "nf.spatial.stimulus"

    static func makeScene(for metadata: NFSpatialRepresentationMetadata, foldedNet: Bool = false) -> Entity {
        let root = Entity()
        root.name = rootEntityName
        guard NFSpatialRenderingSafety.permits(metadata) else { return root }

        if !metadata.points.isEmpty {
            addCoordinateScene(to: root, metadata: metadata)
        } else if metadata.objectDescription.localizedCaseInsensitiveContains("cube net") {
            addCubeNet(to: root, metadata: metadata, folded: foldedNet && metadata.protectedGrammarID == nil)
        } else if metadata.operations.contains(.crossSection) {
            addCrossSectionScene(to: root, metadata: metadata)
        } else {
            addSolid(to: root, metadata: metadata)
        }

        return root
    }

    private static func addCoordinateScene(
        to root: Entity,
        metadata: NFSpatialRepresentationMetadata
    ) {
        let axisLength: Float = 1.5
        root.addChild(model(
            name: "axis.x",
            mesh: .generateBox(size: [axisLength, 0.025, 0.025]),
            color: .systemRed,
            position: [axisLength / 2, 0, 0]
        ))
        root.addChild(model(
            name: "axis.y",
            mesh: .generateBox(size: [0.025, axisLength, 0.025]),
            color: .systemGreen,
            position: [0, axisLength / 2, 0]
        ))
        root.addChild(model(
            name: "axis.z",
            mesh: .generateBox(size: [0.025, 0.025, axisLength]),
            color: .systemBlue,
            position: [0, 0, axisLength / 2]
        ))

        let largestCoordinate = max(
            1,
            metadata.points.flatMap { [abs($0.x), abs($0.y), abs($0.z ?? 0)] }.max() ?? 1
        )
        let scale = 0.95 / Float(largestCoordinate)
        for point in metadata.points {
            let marker = model(
                name: "point.\(point.label)",
                mesh: .generateSphere(radius: 0.11),
                color: .systemIndigo,
                position: [
                    Float(point.x) * scale,
                    Float(point.y) * scale,
                    Float(point.z ?? 0) * scale
                ]
            )
            root.addChild(marker)
        }

        let origin = model(
            name: "origin",
            mesh: .generateSphere(radius: 0.055),
            color: .nfSpatialLabel,
            position: .zero
        )
        root.addChild(origin)
    }

    private static func addCrossSectionScene(
        to root: Entity,
        metadata: NFSpatialRepresentationMetadata
    ) {
        let description = metadata.objectDescription.lowercased()
        let solidMesh: MeshResource
        if description.contains("cylinder") {
            solidMesh = .generateCylinder(height: 1.25, radius: 0.52)
        } else if description.contains("sphere") {
            solidMesh = .generateSphere(radius: 0.7)
        } else {
            solidMesh = .generateBox(size: 1.15, cornerRadius: 0.06)
        }
        root.addChild(model(
            name: stimulusEntityName,
            mesh: solidMesh,
            color: .systemIndigo,
            position: .zero
        ))
        root.addChild(model(
            name: "section.plane",
            mesh: .generateBox(size: [1.75, 0.035, 1.75]),
            color: NFSpatialPlatformColor.systemOrange.withAlphaComponent(0.48),
            position: .zero
        ))
    }


    private static func addCubeNet(to root: Entity, metadata: NFSpatialRepresentationMetadata, folded: Bool) {
        guard let faces = NFCubeNetEngine.displayFaces(encodedDescription: metadata.objectDescription) else { return }
        let object = Entity(); object.name = stimulusEntityName; root.addChild(object)
        let colors: [NFSpatialPlatformColor] = [.systemIndigo, .systemTeal, .systemOrange, .systemPurple, .systemBlue, .systemPink]
        let xMin = faces.map(\.column).min() ?? 0, xMax = faces.map(\.column).max() ?? 0
        let yMin = faces.map(\.row).min() ?? 0, yMax = faces.map(\.row).max() ?? 0
        let centerX = Float(xMin + xMax) / 2, centerY = Float(yMin + yMax) / 2
        for (index, face) in faces.enumerated() {
            let panel = model(name: "face.\(face.label)", mesh: .generateBox(size: [0.98, 0.98, 0.025]),
                color: colors[index], position: .zero)
            if folded {
                func vector(_ value: SIMD3<Int32>) -> SIMD3<Float> { SIMD3(Float(value.x), Float(value.y), Float(value.z)) }
                panel.position = vector(face.normal) * 0.5
                panel.orientation = simd_quatf(simd_float3x3(columns: (vector(face.right), vector(face.up), vector(face.normal))))
            } else { panel.position = [Float(face.column) - centerX, centerY - Float(face.row), 0] }
            let label = model(name: "face-label.\(face.label)",
                mesh: .generateText(face.label, extrusionDepth: 0.003, font: .systemFont(ofSize: 0.22)),
                color: .white, position: [-0.08, -0.08, 0.02])
            panel.addChild(label); object.addChild(panel)
        }
    }

    /// Updates only authored stimulus children. The scene identity, camera target,
    /// selected camera orientation and user orbit are deliberately retained.
    static func updateObject(in root: Entity, metadata: NFSpatialRepresentationMetadata, foldedNet: Bool) {
        guard root.name == rootEntityName, NFSpatialRenderingSafety.permits(metadata) else { return }
        if !metadata.points.isEmpty {
            let largestCoordinate = max(1, metadata.points.flatMap { [abs($0.x), abs($0.y), abs($0.z ?? 0)] }.max() ?? 1)
            let scale = 0.95 / Float(largestCoordinate)
            for point in metadata.points {
                root.findEntity(named: "point.\(point.label)")?.position = [Float(point.x) * scale, Float(point.y) * scale, Float(point.z ?? 0) * scale]
            }
        } else if let faces = NFCubeNetEngine.displayFaces(encodedDescription: metadata.objectDescription) {
            let folded = foldedNet && metadata.protectedGrammarID == nil
            let centerX = Float((faces.map(\.column).min() ?? 0) + (faces.map(\.column).max() ?? 0)) / 2
            let centerY = Float((faces.map(\.row).min() ?? 0) + (faces.map(\.row).max() ?? 0)) / 2
            for face in faces {
                guard let panel = root.findEntity(named: "face.\(face.label)") else { continue }
                if folded {
                    func vector(_ value: SIMD3<Int32>) -> SIMD3<Float> { SIMD3(Float(value.x), Float(value.y), Float(value.z)) }
                    panel.position = vector(face.normal) * 0.5
                    panel.orientation = simd_quatf(simd_float3x3(columns: (vector(face.right), vector(face.up), vector(face.normal))))
                } else {
                    panel.position = [Float(face.column) - centerX, centerY - Float(face.row), 0]
                    panel.orientation = simd_quatf(angle: 0, axis: [0, 0, 1])
                }
            }
        }
    }

    private static func addSolid(
        to root: Entity,
        metadata: NFSpatialRepresentationMetadata
    ) {
        root.addChild(model(
            name: stimulusEntityName,
            mesh: .generateBox(size: [1.55, 0.78, 1.02], cornerRadius: 0.055),
            color: .systemIndigo,
            position: .zero
        ))
        root.addChild(model(
            name: "orientation.marker",
            mesh: .generateSphere(radius: 0.12),
            color: .systemOrange,
            position: [0.58, 0.4, 0.36]
        ))
    }

    private static func model(
        name: String,
        mesh: MeshResource,
        color: NFSpatialPlatformColor,
        position: SIMD3<Float>
    ) -> ModelEntity {
        let material = SimpleMaterial(color: color, roughness: 0.38, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        entity.position = position
        return entity
    }
}


/// Presentation authorization is explicit and never inferred from a spatial
/// description, its answer key or a camera gesture.
enum NFSpatialLearningPhase: String, Equatable, Sendable {
    case independent, savedWorkedSolution, committedFeedback
}

struct NFSpatialToolPolicy: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable { case coordinates, cubeNet, unavailable }
    let kind: Kind
    let allowsObjectChanges: Bool
    static let unavailable = Self(kind: .unavailable, allowsObjectChanges: false)

    static func resolve(exercise: NFExercise?, metadata: NFSpatialRepresentationMetadata,
                        phase: NFSpatialLearningPhase) -> Self {
        guard let exercise, !exercise.assessmentProtected, metadata.protectedGrammarID == nil,
              [.practice, .documentPractice].contains(exercise.purpose),
              exercise.evidenceClass == exercise.purpose.evidenceClass,
              exercise.independentRepresentations.contains(.spatial(metadata)),
              exercise.availabilityReason == nil,
              NFExerciseSchemaValidator.supportsExerciseSchemaVersion(exercise.schemaVersion),
              NFSpatialRenderingSafety.permits(metadata) else { return .unavailable }
        let kind: Kind
        if !metadata.points.isEmpty,
           (metadata.dimension == .twoDimensional ? metadata.points.allSatisfy({ $0.z == nil }) : metadata.points.allSatisfy({ $0.z != nil })),
           metadata.operations.contains(where: { [.coordinateTransform, .rotate, .reflect].contains($0) }) {
            kind = .coordinates
        } else if metadata.points.isEmpty, metadata.operations.contains(.diagramEquationMatch), NFCubeNetEngine.displayFaces(encodedDescription: metadata.objectDescription) != nil {
            kind = .cubeNet
        } else { kind = .unavailable }
        return .init(kind: kind, allowsObjectChanges: kind != .unavailable && phase != .independent)
    }
}

enum NFSpatialCopyOperation: String, CaseIterable, Identifiable, Sendable {
    case rotateX90, rotateY90, rotateZ90, rotateZMinus90
    case reflectX, reflectY, reflectZ
    var id: String { rawValue }
    func title(dimension: NFSpatialDimension, locale: Locale = NFAppLocalization.preferredLocale) -> String {
        let key: String = switch self {
        case .rotateX90: "Rotate object +90° about x"
        case .rotateY90: "Rotate object +90° about y"
        case .rotateZ90: "Rotate object +90° about z"
        case .rotateZMinus90: "Rotate object −90° about z"
        case .reflectX: dimension == .twoDimensional ? "Reflect object across the y-axis" : "Reflect object across the yz-plane"
        case .reflectY: dimension == .twoDimensional ? "Reflect object across the x-axis" : "Reflect object across the xz-plane"
        case .reflectZ: "Reflect object across the xy-plane"
        }
        return NFAppLocalization.localizedCatalogValue(key, locale: locale)
    }
    static func available(for dimension: NFSpatialDimension) -> [Self] {
        dimension == .twoDimensional ? [.rotateZ90, .rotateZMinus90, .reflectX, .reflectY] : allCases
    }
}

/// Signed axis permutations are exact: there is no cumulative trigonometric
/// drift, coordinate scaling, response binding or modification of the source.
struct NFSpatialObjectCopy: Equatable, Sendable {
    private(set) var axes: [Int] = [1, 2, 3]
    private(set) var isFolded = false
    init() {}
    static let authored = Self()

    mutating func apply(_ operation: NFSpatialCopyOperation, policy: NFSpatialToolPolicy,
                        metadata: NFSpatialRepresentationMetadata) -> Bool {
        guard policy.allowsObjectChanges, policy.kind == .coordinates,
              NFSpatialCopyOperation.available(for: metadata.dimension).contains(operation) else { return false }
        let old = axes
        switch operation {
        case .rotateX90: axes = [old[0], -old[2], old[1]]
        case .rotateY90: axes = [old[2], old[1], -old[0]]
        case .rotateZ90: axes = [-old[1], old[0], old[2]]
        case .rotateZMinus90: axes = [old[1], -old[0], old[2]]
        case .reflectX: axes = [-old[0], old[1], old[2]]
        case .reflectY: axes = [old[0], -old[1], old[2]]
        case .reflectZ: axes = [old[0], old[1], -old[2]]
        }
        return true
    }
    mutating func setFolded(_ folded: Bool, policy: NFSpatialToolPolicy) -> Bool {
        guard policy.allowsObjectChanges, policy.kind == .cubeNet else { return false }
        isFolded = folded; return true
    }
    mutating func reset() { self = .authored }
    func points(from original: [NFSpatialPoint]) -> [NFSpatialPoint] {
        original.map { point in
            let source = [point.x, point.y, point.z ?? 0]
            let transformed = axes.map { axis in source[abs(axis) - 1] * (axis < 0 ? -1 : 1) }
            return .init(label: point.label, x: transformed[0], y: transformed[1], z: point.z == nil ? nil : transformed[2])
        }
    }
    func metadata(from original: NFSpatialRepresentationMetadata, policy: NFSpatialToolPolicy) -> NFSpatialRepresentationMetadata {
        guard policy.allowsObjectChanges, policy.kind == .coordinates else { return original }
        return .init(stimulusCategory: original.stimulusCategory, dimension: original.dimension,
            objectDescription: original.objectDescription, viewpoint: original.viewpoint, operations: original.operations,
            points: points(from: original.points), axisLabels: original.axisLabels,
            accessibilityDescription: original.accessibilityDescription, assetName: original.assetName,
            protectedGrammarID: original.protectedGrammarID, difficultyParameters: original.difficultyParameters)
    }
    func description(original: NFSpatialRepresentationMetadata, policy: NFSpatialToolPolicy, locale: Locale) -> String? {
        guard policy.allowsObjectChanges else { return nil }
        if policy.kind == .cubeNet {
            guard isFolded, let faces = NFCubeNetEngine.displayFaces(encodedDescription: original.objectDescription) else {
                return NFAppLocalization.localized("Object copy: the original unfolded net.", locale: locale)
            }
            return faces.map { face in
                NFAppLocalization.localized("Face \(face.label) points toward \(face.directionTitle(locale: locale)).", locale: locale)
            }.joined(separator: " ")
        }
        return points(from: original.points).map { point in
            let x = NFSpatialRenderingSafety.coordinateLabel(point.x, locale: locale)
            let y = NFSpatialRenderingSafety.coordinateLabel(point.y, locale: locale)
            if let z = point.z {
                return NFAppLocalization.localized("Object copy \(point.label): x \(x), y \(y), z \(NFSpatialRenderingSafety.coordinateLabel(z, locale: locale)).", locale: locale)
            }
            return NFAppLocalization.localized("Object copy \(point.label): x \(x), y \(y).", locale: locale)
        }.joined(separator: " ")
    }
}

/// Orthographic projection is display-only. The full original coordinate tuple
/// remains available beside it, including the axis omitted from this view.
enum NFSpatialOrthographicProjection {
    static func components(_ point: NFSpatialPoint, camera: String) -> (horizontal: Double, vertical: Double) {
        switch camera {
        case "Side": (-(point.z ?? 0), point.y)
        case "Top": (point.x, -(point.z ?? 0))
        default: (point.x, point.y)
        }
    }
    static func axisLabels(metadata: NFSpatialRepresentationMetadata, camera: String) -> [String] {
        let axes = metadata.axisLabels
        let x = axes.first ?? "x", y = axes.dropFirst().first ?? "y", z = axes.dropFirst(2).first ?? "z"
        switch camera {
        case "Side": return ["−" + z, y]
        case "Top": return [x, "−" + z]
        default: return [x, y]
        }
    }
}


/// A post-answer demonstration state, distinct from both camera pose and the
/// immutable learner response. It cannot advance during independent answering.
struct NFSpatialStructureCopyState: Equatable, Sendable {
    private(set) var completedRotations = 0
    mutating func advance(contract: NFSpatialStructureContract, phase: NFSpatialLearningPhase) -> Bool {
        guard contract.isSupported, phase != .independent, case let .faces(value) = contract.structure,
              completedRotations < value.rotations.count else { return false }
        completedRotations += 1; return true
    }
    mutating func reset() { completedRotations = 0 }
    func rotations(contract: NFSpatialStructureContract, phase: NFSpatialLearningPhase) -> [NFSpatialStructureGeometry.Rotation] {
        guard contract.isSupported, phase != .independent, case let .faces(value) = contract.structure else { return [] }
        return Array(value.rotations.prefix(completedRotations))
    }
}

struct NFSpatialStructureStimulusView: View {
    let contract: NFSpatialStructureContract
    let phase: NFSpatialLearningPhase
    let prefersReducedMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var native = true
    @State private var camera = "Authored view"
    @State private var resetID = 0
    @State private var copy = NFSpatialStructureCopyState()
    private var allowsCamera: Bool { if case .faces = contract.structure { return true }; return phase != .independent }
    private var rotations: [NFSpatialStructureGeometry.Rotation] { copy.rotations(contract:contract,phase:phase) }

    var body: some View {
        if contract.isSupported {
            VStack(alignment:.leading,spacing:14) {
                Text(contract.sourceDescription).font(.body)
                switch contract.structure {
                case .faces: objectView; faceTable; rotationControls
                case let .top(value): objectView; cellTable(value.cells); footprintChoices(value)
                case let .views(value): constraintViews(value)
                }
                Text(contract.text("The coordinate descriptions support geometry practice; they are not a validated substitute for a visual assessment.","座標の説明は幾何の練習を支援しますが、視覚課題と同等だと検証された代替評価ではありません。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children:.contain)
            .accessibilityIdentifier("spatial-retained-structure")
            .onChange(of:contract) { _,_ in copy.reset(); camera="Authored view"; resetID += 1 }
            .onChange(of:phase) { _,value in if value == .independent { copy.reset(); camera="Authored view" } }
        }
    }
    private var objectView: some View {
        VStack(alignment:.leading,spacing:10) {
            Menu {
                Button { native = true } label: { Label("Native 3D", systemImage: native ? "checkmark" : "cube") }
                    .accessibilityIdentifier("spatial-structure-mode-native")
                Button { native = false } label: { Label("Static 2D", systemImage: native ? "square" : "checkmark") }
                    .accessibilityIdentifier("spatial-structure-mode-static")
            } label: {
                VStack(alignment:.leading,spacing:3) {
                    Text("Spatial rendering mode").font(.caption)
                    Text(LocalizedStringKey(native ? "Native 3D" : "Static 2D"))
                }.frame(minWidth:44,minHeight:58).contentShape(Rectangle())
            }.accessibilityIdentifier("spatial-structure-rendering-mode")
                .accessibilityValue(Text(LocalizedStringKey(native ? "Native 3D" : "Static 2D")))
            if native {
                NFSpatialStructureRealityView(contract:contract,rotations:rotations,camera:camera,
                    allowsOrbit:allowsCamera && !prefersReducedMotion && !reducedMotion)
                    .id("\(camera)-\(resetID)")
            } else {
                NFSpatialStructureDrawing(contract:contract,rotations:rotations,camera:camera)
                    .frame(height:270).accessibilityHidden(true)
            }
            ViewThatFits(in:.horizontal) {
                HStack { cameraControls }
                VStack(alignment:.leading) { cameraControls }
            }
            Text(contract.text("Camera changes keep the original object and your response unchanged. Object replay is available only after saving the response.","カメラを変えても元の物体と回答は変わりません。物体の再現操作は回答を保存した後だけ利用できます。"))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var cameraControls: some View {
        Menu {
            Picker("Camera view",selection:$camera) {
                Text("Authored view").tag("Authored view"); Text("Front").tag("Front")
                Text("Side").tag("Side"); Text("Top").tag("Top")
            }
        } label: {
            VStack(alignment:.leading,spacing:3) {
                Text("Camera view").font(.caption)
                Text(LocalizedStringKey(camera))
            }.frame(minWidth:44,minHeight:58).contentShape(Rectangle())
        }.disabled(!allowsCamera).accessibilityIdentifier("spatial-structure-camera")
            .accessibilityValue(Text(LocalizedStringKey(camera)))
        Button {
            camera="Authored view"; resetID += 1
            announce(contract.text("Camera reset to the authored view.","カメラを元の視点に戻しました。"))
        } label: {
            Text("Reset view").frame(minWidth:44,minHeight:58).contentShape(Rectangle())
        }.accessibilityIdentifier("spatial-structure-camera-reset")
    }
    private var faceTable: some View {
        VStack(alignment:.leading,spacing:7) {
            Text(rotations.isEmpty ? contract.text("Initial face normals","元の面の法線") : contract.text("Demonstration face normals","解説用コピーの面の法線")).font(.headline)
            ForEach(Array(zip(NFSpatialStructureGeometry.FaceRotation.labels,NFSpatialStructureGeometry.Direction.allCases)),id:\.0) { label,direction in
                let vector = NFSpatialStructureGeometry.transform(direction.vector,by:rotations)
                let destination = NFSpatialStructureGeometry.Direction.allCases.first { $0.vector == vector }?.symbol ?? direction.symbol
                Text(contract.text("Face \(label): outward normal \(destination)","面\(label)：外向きの法線 \(destination)"))
                    .font(.body.monospaced()).accessibilityIdentifier("spatial-face-"+label)
            }
            if case let .faces(value) = contract.structure {
                Text(contract.text("Target direction: \(value.query.symbol)","問われている向き：\(value.query.symbol)"))
                    .font(.headline).accessibilityIdentifier("spatial-target-direction")
            }
        }
    }
    private var rotationControls: some View {
        VStack(alignment:.leading,spacing:10) {
            if case let .faces(value) = contract.structure {
                ForEach(Array(value.rotations.enumerated()),id:\.offset) { index,rotation in
                    VStack(alignment:.leading,spacing:6) {
                        Text("\(index+1). " + contract.rotationDescription(rotation)).font(.subheadline)
                        NFSpatialRotationInstructionDrawing(axis:rotation.axis.rawValue,degrees:rotation.quarterTurns*90)
                            .frame(height:95).accessibilityHidden(true)
                    }
                }
                Text(contract.text("Positive angle means counterclockwise viewed from the positive axis toward the origin.","正の角度は、正の軸から原点を見た反時計回りです。"))
                    .font(.footnote)
                HStack {
                    Button {
                        if copy.advance(contract:contract,phase:phase) {
                            announce(contract.text("Rotation step \(copy.completedRotations) of \(value.rotations.count).","回転の\(value.rotations.count)段階中、\(copy.completedRotations)段階目です。") + " " + currentFaceDescription)
                        }
                    } label: {
                        Text(contract.text("Step object rotation","物体の回転を1段階進める"))
                            .frame(minWidth:44,minHeight:58).contentShape(Rectangle())
                    }.buttonStyle(.bordered).disabled(phase == .independent || copy.completedRotations >= value.rotations.count)
                        .accessibilityIdentifier("spatial-structure-step")
                    Button { copy.reset(); announce(contract.sourceDescription) } label: {
                        Text("Reset object").frame(minWidth:44,minHeight:58).contentShape(Rectangle())
                    }.buttonStyle(.bordered).disabled(phase == .independent).accessibilityIdentifier("spatial-structure-reset")
                }
            }
        }
    }
    private var currentFaceDescription: String {
        zip(NFSpatialStructureGeometry.FaceRotation.labels,NFSpatialStructureGeometry.Direction.allCases).map { label,direction in
            let v = NFSpatialStructureGeometry.transform(direction.vector,by:rotations)
            let d = NFSpatialStructureGeometry.Direction.allCases.first { $0.vector == v }?.symbol ?? direction.symbol
            return contract.text("Face \(label): \(d).","面\(label)：\(d)。")
        }.joined(separator:" ")
    }
    private func cellTable(_ cells: [NFSpatialStructureGeometry.Cell]) -> some View {
        Text(contract.text("Occupied cells (x, y, z): ","占有セル (x, y, z)：") + cells.map { "(\($0.x), \($0.y), \($0.z))" }.joined(separator:"; "))
            .font(.body.monospaced()).textSelection(.enabled).accessibilityIdentifier("spatial-occupied-cells")
    }
    private func footprintChoices(_ value: NFSpatialStructureGeometry.TopView) -> some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:240),spacing:14)],spacing:14) {
            ForEach(value.choices.indices,id:\.self) { index in
                VStack(alignment:.leading,spacing:8) {
                    Text(contract.text("Footprint \(NFSpatialStructureContract.choiceID(index))","輪郭\(NFSpatialStructureContract.choiceID(index))")).font(.headline)
                    NFSpatialPlanDrawing(squares:value.choices[index],xLabel:"x",yLabel:"y").frame(height:180).accessibilityHidden(true)
                    Text(value.choices[index].map { "(\($0.x), \($0.y))" }.joined(separator:"; ")).font(.body.monospaced())
                }.accessibilityElement(children:.combine)
            }
        }
    }
    private func constraintViews(_ value: NFSpatialStructureGeometry.ViewConstraints) -> some View {
        VStack(alignment:.leading,spacing:14) {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:240))],spacing:14) {
                projectionCard(title:contract.text("Supplied front view","与えられた正面図"),heights:value.frontHeights,horizontal:"x")
                projectionCard(title:contract.text("Supplied side view","与えられた側面図"),heights:value.sideHeights,horizontal:"y")
            }
            ForEach(value.candidates.indices,id:\.self) { index in
                VStack(alignment:.leading,spacing:10) {
                    Text(contract.text("Assembly \(NFSpatialStructureContract.choiceID(index))","積み方\(NFSpatialStructureContract.choiceID(index))")).font(.headline)
                    NFSpatialOccupiedDrawing(cells:value.candidates[index],camera:"Authored view").frame(height:200).accessibilityHidden(true)
                    cellTable(value.candidates[index])
                }.padding(10).background(.thinMaterial,in:RoundedRectangle(cornerRadius:12))
            }
        }
    }
    private func projectionCard(title: String, heights: [Int], horizontal: String) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title).font(.headline)
            NFSpatialPlanDrawing(squares:heights.enumerated().flatMap { x,height in (0..<height).map { NFSpatialStructureGeometry.Square(x:x,y:$0) } },xLabel:horizontal,yLabel:"z")
                .frame(height:170).accessibilityHidden(true)
            Text(contract.text("Column heights from \(horizontal) = 0: ","\(horizontal) = 0から順に列の高さ：") + heights.map(String.init).joined(separator:", "))
                .font(.body.monospaced())
        }.accessibilityElement(children:.combine)
    }
    private func announce(_ text: String) { AccessibilityNotification.Announcement(text).post() }
}

private struct NFSpatialPlanDrawing: View {
    let squares: [NFSpatialStructureGeometry.Square]
    let xLabel: String
    let yLabel: String
    var body: some View {
        Canvas { context,size in
            let maxX = squares.map(\.x).max() ?? 1, maxY = squares.map(\.y).max() ?? 1
            let unit = max(1,min((size.width-60)/CGFloat(maxX+2),(size.height-45)/CGFloat(maxY+2)))
            let origin = CGPoint(x:35,y:size.height-30)
            for square in squares {
                let rect = CGRect(x:origin.x+CGFloat(square.x)*unit,y:origin.y-CGFloat(square.y+1)*unit,width:unit,height:unit)
                context.fill(Path(rect),with:.color(NFTheme.indigo.opacity(0.22)))
                context.stroke(Path(rect),with:.color(.primary),lineWidth:1.5)
            }
            for x in 0...maxX { context.draw(Text(String(x)).font(.caption),at:CGPoint(x:origin.x+(CGFloat(x)+0.5)*unit,y:origin.y+12)) }
            for y in 0...maxY { context.draw(Text(String(y)).font(.caption),at:CGPoint(x:origin.x-14,y:origin.y-(CGFloat(y)+0.5)*unit)) }
            context.draw(Text(xLabel).font(.caption.bold()),at:CGPoint(x:origin.x+CGFloat(maxX+1)*unit+12,y:origin.y))
            context.draw(Text(yLabel).font(.caption.bold()),at:CGPoint(x:origin.x,y:origin.y-CGFloat(maxY+1)*unit-12))
        }
    }
}

private enum NFSpatialStructureDrawingGeometry {
    static func project(_ v: SIMD3<Double>, camera: String) -> SIMD2<Double> {
        switch camera { case "Front": [v.x,-v.y]; case "Side": [-v.z,-v.y]; case "Top": [v.x,v.z]; default: [sqrt(0.5)*(v.x-v.z),-sqrt(2.0/3.0)*v.y+sqrt(1.0/6.0)*(v.x+v.z)] }
    }
    static func visible(_ normal: SIMD3<Double>, camera: String) -> Bool {
        switch camera { case "Front": normal.z > 0; case "Side": normal.x > 0; case "Top": normal.y > 0; default: normal.x+normal.y+normal.z > 0 }
    }
    static let frames: [(normal:SIMD3<Double>,right:SIMD3<Double>,up:SIMD3<Double>)] = [
        ([1,0,0],[0,0,-1],[0,1,0]),([-1,0,0],[0,0,1],[0,1,0]),
        ([0,1,0],[1,0,0],[0,0,-1]),([0,-1,0],[1,0,0],[0,0,1]),
        ([0,0,1],[1,0,0],[0,1,0]),([0,0,-1],[-1,0,0],[0,1,0])]
}
private struct NFSpatialStructureDrawing: View {
    let contract: NFSpatialStructureContract
    let rotations: [NFSpatialStructureGeometry.Rotation]
    let camera: String
    var body: some View {
        if case let .top(value) = contract.structure { NFSpatialOccupiedDrawing(cells:value.cells,camera:camera) }
        else { cube }
    }
    private var cube: some View {
        Canvas { context,size in
            let scale = min(size.width,size.height)*0.56
            func transformed(_ v: SIMD3<Double>) -> SIMD3<Double> {
                let a = NFSpatialStructureGeometry.transform([Int(v.x),Int(v.y),Int(v.z)],by:rotations)
                return SIMD3(Double(a[0]),Double(a[1]),Double(a[2]))
            }
            func point(_ v: SIMD3<Double>) -> CGPoint {
                let p = NFSpatialStructureDrawingGeometry.project(v,camera:camera)
                return CGPoint(x:size.width/2+CGFloat(p.x)*scale,y:size.height/2+CGFloat(p.y)*scale)
            }
            for (index,frame) in NFSpatialStructureDrawingGeometry.frames.enumerated() {
                let n = transformed(frame.normal), r = transformed(frame.right)*0.5, u = transformed(frame.up)*0.5
                guard NFSpatialStructureDrawingGeometry.visible(n,camera:camera) else { continue }
                let c = n*0.5
                var path = Path(); path.addLines([c-r-u,c+r-u,c+r+u,c-r+u].map(point)); path.closeSubpath()
                context.fill(path,with:.color(NFTheme.indigo.opacity(n.y > 0 ? 0.15:0.3)))
                context.stroke(path,with:.color(.primary),lineWidth:2)
                context.draw(Text(NFSpatialStructureGeometry.FaceRotation.labels[index]).font(.title2.bold()),at:point(c))
            }
            for (label,end) in [("+x",SIMD3<Double>(1,0,0)),("+y",SIMD3<Double>(0,1,0)),("+z",SIMD3<Double>(0,0,1))] {
                var axis = Path(); axis.move(to:point(.zero)); axis.addLine(to:point(end*0.9))
                context.stroke(axis,with:.color(.primary.opacity(0.6)),style:StrokeStyle(lineWidth:1,dash:[4,3]))
                context.draw(Text(label).font(.caption.bold()),at:point(end))
            }
        }
    }
}
private struct NFSpatialOccupiedDrawing: View {
    let cells: [NFSpatialStructureGeometry.Cell]
    let camera: String
    var body: some View {
        Canvas { context,size in
            guard NFSpatialStructureGeometry.permits(cells) else { return }
            func world(_ cell: NFSpatialStructureGeometry.Cell) -> SIMD3<Double> { [Double(cell.x)+0.5,Double(cell.z)+0.5,-Double(cell.y)-0.5] }
            let extent = Double(max(max(cells.map(\.x).max() ?? 0,cells.map(\.y).max() ?? 0),cells.map(\.z).max() ?? 0)+1)
            let scale = min(size.width/(CGFloat(extent)*2.8),size.height/(CGFloat(extent)*2.1))
            let center = SIMD3<Double>(extent/2,extent/2,-extent/2)
            func point(_ v: SIMD3<Double>) -> CGPoint {
                let p = NFSpatialStructureDrawingGeometry.project(v-center,camera:camera)
                return CGPoint(x:size.width/2+CGFloat(p.x)*scale,y:size.height/2+CGFloat(p.y)*scale)
            }
            let occupied = Set(cells)
            for cell in cells.sorted(by:{ let a=world($0),b=world($1);return a.x+a.y+a.z < b.x+b.y+b.z }) {
                let c = world(cell)
                for frame in NFSpatialStructureDrawingGeometry.frames where NFSpatialStructureDrawingGeometry.visible(frame.normal,camera:camera) {
                    let neighbor = NFSpatialStructureGeometry.Cell(x:cell.x+Int(frame.normal.x),y:cell.y-Int(frame.normal.z),z:cell.z+Int(frame.normal.y))
                    guard !occupied.contains(neighbor) else { continue }
                    let n=frame.normal*0.5,r=frame.right*0.5,u=frame.up*0.5
                    var path=Path();path.addLines([c+n-r-u,c+n+r-u,c+n+r+u,c+n-r+u].map(point));path.closeSubpath()
                    context.fill(path,with:.color(NFTheme.indigo.opacity(frame.normal.y > 0 ? 0.18:0.35)))
                    context.stroke(path,with:.color(.primary),lineWidth:1.3)
                }
            }
            for (label,end) in [("+x",SIMD3<Double>(extent+0.3,0,0)),("+y",SIMD3<Double>(0,0,-extent-0.3)),("+z",SIMD3<Double>(0,extent+0.3,0))] {
                context.draw(Text(label).font(.caption.bold()),at:point(end))
            }
        }
    }
}

private struct NFSpatialStructureRealityView: View {
    let contract: NFSpatialStructureContract
    let rotations: [NFSpatialStructureGeometry.Rotation]
    let camera: String
    let allowsOrbit: Bool
    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let root = NFSpatialRealitySceneFactory.makeStructureScene(contract:contract,rotations:rotations)
            if camera == "Authored view" { root.orientation = simd_quatf(angle:Float(atan(1/sqrt(2.0))),axis:[1,0,0]) * simd_quatf(angle: -.pi/4,axis:[0,1,0]) }
            if camera == "Side" { root.orientation = simd_quatf(angle: -.pi/2,axis:[0,1,0]) }
            if camera == "Top" { root.orientation = simd_quatf(angle: .pi/2,axis:[1,0,0]) }
            content.add(root);content.cameraTarget=root
        } update: { content in
            if let root = content.entities.first {
                NFSpatialRealitySceneFactory.updateStructureScene(root,contract:contract,rotations:rotations)
            }
        } placeholder: { ProgressView("Preparing 3D model") }
        .realityViewCameraControls(allowsOrbit ? .orbit : .none)
        .frame(minHeight:250,idealHeight:280).accessibilityHidden(true)
    }
}

extension NFSpatialRealitySceneFactory {
    static func makeStructureScene(contract: NFSpatialStructureContract, rotations: [NFSpatialStructureGeometry.Rotation] = []) -> Entity {
        let root=Entity();root.name="nf.spatial.structure"
        guard contract.isSupported else { return root }
        let object=Entity();object.name="nf.spatial.structure.object";root.addChild(object)
        switch contract.structure {
        case .faces:
            for (index,frame) in NFSpatialStructureDrawingGeometry.frames.enumerated() {
                let label=NFSpatialStructureGeometry.FaceRotation.labels[index]
                func float(_ v:SIMD3<Double>) -> SIMD3<Float> { [Float(v.x),Float(v.y),Float(v.z)] }
                let panel=model(name:"structure.face."+label,mesh:.generateBox(size:[0.98,0.98,0.025]),color:.systemIndigo,position:float(frame.normal)*0.5)
                panel.orientation=simd_quatf(simd_float3x3(columns:(float(frame.right),float(frame.up),float(frame.normal))))
                let text=model(name:"structure.face-label."+label,mesh:.generateText(label,extrusionDepth:0.003,font:.systemFont(ofSize:0.24)),color:.white,position:[-0.08,-0.08,0.02])
                panel.addChild(text);object.addChild(panel)
            }
        case let .top(value):
            for cell in value.cells {
                object.addChild(model(name:"structure.cell."+cell.token,mesh:.generateBox(size:0.98),color:.systemIndigo,
                    position:[Float(cell.x)+0.5,Float(cell.z)+0.5,-Float(cell.y)-0.5]))
            }
        case .views: break
        }
        if case let .top(value) = contract.structure {
            let x=Float((value.cells.map(\.x).max() ?? 0)+1),y=Float((value.cells.map(\.y).max() ?? 0)+1),z=Float((value.cells.map(\.z).max() ?? 0)+1)
            let scale:Float=1.6/max(x,max(y,z));object.scale=[scale,scale,scale]
            object.position=[-x*scale/2,-z*scale/2,y*scale/2]
        }
        if case .faces = contract.structure {
            for (axis,position,size) in [("+x",SIMD3<Float>(0.75,0,0),SIMD3<Float>(1.5,0.012,0.012)),("+y",SIMD3<Float>(0,0.75,0),SIMD3<Float>(0.012,1.5,0.012)),("+z",SIMD3<Float>(0,0,0.75),SIMD3<Float>(0.012,0.012,1.5))] {
                root.addChild(model(name:"structure.axis."+axis,mesh:.generateBox(size:size),color:.nfSpatialLabel,position:position))
                root.addChild(model(name:"structure.axis-label."+axis,mesh:.generateText(axis,extrusionDepth:0.001,font:.systemFont(ofSize:0.12)),color:.nfSpatialLabel,position:position*2))
            }
        }
        updateStructureScene(root,contract:contract,rotations:rotations)
        return root
    }
    static func updateStructureScene(_ root: Entity, contract: NFSpatialStructureContract, rotations: [NFSpatialStructureGeometry.Rotation]) {
        guard contract.isSupported, case .faces = contract.structure,
              let object=root.findEntity(named:"nf.spatial.structure.object"),rotations.count <= 2,rotations.allSatisfy(\.isValid) else { return }
        func axis(_ source:[Int]) -> SIMD3<Float> {
            let v=NFSpatialStructureGeometry.transform(source,by:rotations);return [Float(v[0]),Float(v[1]),Float(v[2])]
        }
        object.orientation=simd_quatf(simd_float3x3(columns:(axis([1,0,0]),axis([0,1,0]),axis([0,0,1]))))
    }
}

/// The direction cue is drawn in the stated view from the positive axis.
/// It conveys the operation, never the cube's computed destination labels.
private struct NFSpatialRotationInstructionDrawing: View {
    let axis:String
    let degrees:Int
    var body:some View {
        Canvas { context,size in
            let center=CGPoint(x:60,y:48),radius:CGFloat=30
            func point(_ angle:Double) -> CGPoint { CGPoint(x:center.x+radius*CGFloat(cos(angle)),y:center.y-radius*CGFloat(sin(angle))) }
            let angles=(0...max(1,degrees/5)).map { Double($0)*5.0*Double.pi/180 }
            var curve=Path();curve.addLines(angles.map(point))
            context.stroke(curve,with:.color(.primary),lineWidth:2)
            let angle=Double(degrees)*Double.pi/180,tip=point(angle)
            let tangent=CGVector(dx:CGFloat(-sin(angle)),dy:CGFloat(-cos(angle)))
            let base=CGPoint(x:tip.x-8*tangent.dx,y:tip.y-8*tangent.dy)
            var arrow=Path();arrow.move(to:CGPoint(x:base.x-4*tangent.dy,y:base.y+4*tangent.dx));arrow.addLine(to:tip);arrow.addLine(to:CGPoint(x:base.x+4*tangent.dy,y:base.y-4*tangent.dx))
            context.stroke(arrow,with:.color(.primary),lineWidth:2)
            context.draw(Text("⊙ +"+axis).font(.caption.bold()),at:center)
            context.draw(Text(verbatim:"+\(degrees)°").font(.headline),at:CGPoint(x:130,y:48))
        }
    }
}


/// A worked-copy state only. Independent rendering always returns the authored
/// point even if a retained view happens to carry a later demonstration step.
struct NFCoordinateTransformCopyState: Equatable, Sendable {
    private(set) var completedOperations = 0
    mutating func advance(contract: NFCoordinateTransformContract,phase: NFSpatialLearningPhase) -> Bool {
        guard contract.isSupported,phase != .independent,completedOperations < contract.task.operations.count else { return false }
        completedOperations += 1;return true
    }
    mutating func reset() { completedOperations=0 }
    func visibleStep(contract: NFCoordinateTransformContract,phase: NFSpatialLearningPhase) -> Int {
        guard contract.isSupported,phase != .independent else { return 0 }
        return min(completedOperations,contract.task.operations.count)
    }
}
struct NFCoordinateTransformStimulusView: View {
    let contract: NFCoordinateTransformContract
    let phase: NFSpatialLearningPhase
    @State private var copy=NFCoordinateTransformCopyState()
    private var visibleStep: Int { copy.visibleStep(contract:contract,phase:phase) }
    var body: some View {
        if contract.isSupported {
            VStack(alignment:.leading,spacing:12) {
                Text(contract.text("Original coordinate plane","元の座標平面")).font(.headline)
                NFCoordinateTransformDrawing(contract:contract,step:visibleStep,showsTriangle:phase != .independent)
                    .frame(minHeight:280,idealHeight:340).accessibilityHidden(true)
                Text(contract.sourceDescription).font(.body)
                    .accessibilityIdentifier("coordinate-transform-original")
                Text(contract.text("Response fields: x (grid units); y (grid units).","回答欄：x（格子単位）、y（格子単位）。"))
                    .accessibilityIdentifier("coordinate-transform-units")
                if phase != .independent {
                    Text(contract.text("Worked copy after \(visibleStep) \(visibleStep == 1 ? "operation" : "operations"): P = ","\(visibleStep)回の操作後の解説用コピー：P = ")+contract.coordinate(contract.task.steps[visibleStep]))
                        .font(.headline).accessibilityIdentifier("coordinate-transform-copy")
                    HStack {
                        Button {
                            if copy.advance(contract:contract,phase:phase) { announceVisiblePoint() }
                        } label: {
                            Text(contract.text("Step transformation","変換を1段階進める"))
                                .frame(minWidth:44,minHeight:58).contentShape(Rectangle())
                        }.buttonStyle(.bordered)
                            .disabled(visibleStep >= contract.task.operations.count)
                            .accessibilityIdentifier("coordinate-transform-step")
                        Button { copy.reset();announceVisiblePoint() } label: {
                            Text(contract.text("Reset worked copy","解説用コピーを元に戻す"))
                                .frame(minWidth:44,minHeight:58).contentShape(Rectangle())
                        }.buttonStyle(.bordered).accessibilityIdentifier("coordinate-transform-reset")
                    }
                    Text(workedTriangleDescription).font(.body.monospaced())
                        .accessibilityIdentifier("coordinate-transform-triangle")
                    Text(contract.text("The outlined triangle makes orientation visible in this explanation. Your saved point response remains unchanged.","輪郭の三角形は、この解説で向きを見えるようにしています。保存済みの点の回答は変わりません。"))
                        .font(.footnote)
                } else {
                    Text(contract.text("Only the original point and transformation givens are shown before saving. The worked copy opens afterward.","保存前は、元の点と変換の条件だけを表示します。解説用コピーは保存後に開きます。"))
                        .font(.footnote)
                }
                Text(contract.text("This coordinate task measures symbolic geometry practice; it is not a validated replacement for a visual mental-rotation assessment.","この座標課題は記号による幾何の練習です。視覚的な心的回転の評価と同等だと検証された代替課題ではありません。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }.accessibilityElement(children:.contain).accessibilityIdentifier("coordinate-transform-stimulus")
                .onChange(of:contract) { _,_ in copy.reset() }
                .onChange(of:phase) { _,value in if value == .independent { copy.reset() } }
        }
    }
    private var workedTriangleDescription: String {
        let affine=contract.task.operations.prefix(visibleStep).reduce(NFCoordinateTransformGeometry.Affine.identity) { $1.affine!.after($0) }
        return contract.text("Worked triangle coordinates: ","解説用三角形の座標：")+contract.referenceTriangle.enumerated().map {
            ($0.offset == 0 ? "P′" : "T\($0.offset)")+" = "+contract.coordinate(affine.applying($0.element))
        }.joined(separator:"; ")
    }
    private func announceVisiblePoint() {
        let operation=visibleStep > 0 ? contract.operationDescription(contract.task.operations[visibleStep-1])+" " : ""
        let value=operation+contract.text("Worked copy after \(visibleStep) \(visibleStep == 1 ? "operation" : "operations"). P is ","\(visibleStep)回の操作後の解説用コピー。Pの座標は")+contract.coordinate(contract.task.steps[visibleStep])
        #if os(iOS)
        UIAccessibility.post(notification:.announcement,argument:value)
        #elseif os(macOS)
        if let window=NSApp.keyWindow {
            NSAccessibility.post(element:window,notification:.announcementRequested,userInfo:[.announcement:value,.priority:NSAccessibilityPriorityLevel.high.rawValue])
        }
        #endif
    }
}
private struct NFCoordinateTransformDrawing: View {
    let contract: NFCoordinateTransformContract
    let step: Int
    let showsTriangle: Bool
    var body: some View {
        Canvas { context,size in
            let side=max(1,min(size.width-56,size.height-52)),unit=side/24
            let left=(size.width-side)/2,top=(size.height-side)/2
            func screen(_ p: NFCoordinateTransformGeometry.Point) -> CGPoint {
                .init(x:left+CGFloat(p.x+12)*unit,y:top+CGFloat(12-p.y)*unit)
            }
            func segment(_ a: NFCoordinateTransformGeometry.Point,_ b: NFCoordinateTransformGeometry.Point,color: Color,dash: [CGFloat]=[],width: CGFloat=1) {
                var line=Path();line.move(to:screen(a));line.addLine(to:screen(b))
                context.stroke(line,with:.color(color),style:.init(lineWidth:width,dash:dash))
            }
            func label(_ text: String,at p: CGPoint,color: Color = .primary) {
                context.draw(Text(text).font(.caption2).foregroundStyle(color),at:p)
            }
            for i in -12...12 {
                segment(.init(x:i,y:-12),.init(x:i,y:12),color:.secondary.opacity(i == 0 ? 0.8 : 0.15),width:i == 0 ? 1.6 : 0.7)
                segment(.init(x:-12,y:i),.init(x:12,y:i),color:.secondary.opacity(i == 0 ? 0.8 : 0.15),width:i == 0 ? 1.6 : 0.7)
                if i % 4 == 0 && i != 0 {
                    let xp=screen(.init(x:i,y:0)),yp=screen(.init(x:0,y:i))
                    label(String(i),at:.init(x:xp.x,y:xp.y+10));label(String(i),at:.init(x:yp.x-12,y:yp.y))
                }
            }
            label(contract.text("x (grid units)","x（格子単位）"),at:.init(x:left+side/2,y:top+side+18))
            label(contract.text("y (grid units)","y（格子単位）"),at:.init(x:left+side/2,y:top-14))
            for (index,operation) in contract.task.operations.enumerated() {
                switch operation {
                case let .rotate(center,_):
                    let p=screen(center);var cross=Path();cross.move(to:.init(x:p.x-5,y:p.y-5));cross.addLine(to:.init(x:p.x+5,y:p.y+5));cross.move(to:.init(x:p.x-5,y:p.y+5));cross.addLine(to:.init(x:p.x+5,y:p.y-5));context.stroke(cross,with:.color(.orange),lineWidth:2)
                    label("C\(index+1)",at:.init(x:p.x+12,y:p.y+10),color:.orange)
                case let .reflect(line,offset):
                    let ends: (NFCoordinateTransformGeometry.Point,NFCoordinateTransformGeometry.Point)
                    switch line {
                    case .vertical: ends=(.init(x:offset,y:-12),.init(x:offset,y:12))
                    case .horizontal: ends=(.init(x:-12,y:offset),.init(x:12,y:offset))
                    case .risingDiagonal: ends=(.init(x:-12,y:-12),.init(x:12,y:12))
                    case .fallingDiagonal: ends=(.init(x:-12,y:12),.init(x:12,y:-12))
                    }
                    segment(ends.0,ends.1,color:.orange,dash:[5,3],width:2)
                case .translate: break
                }
            }
            let original=screen(contract.task.point)
            context.fill(Path(ellipseIn:.init(x:original.x-5,y:original.y-5,width:10,height:10)),with:.color(.blue))
            label("P",at:.init(x:original.x-10,y:original.y-12),color:.blue)
            if showsTriangle {
                let moves=Array(contract.task.operations.prefix(max(0,min(step,contract.task.operations.count))))
                let affine=moves.reduce(NFCoordinateTransformGeometry.Affine.identity) { $1.affine!.after($0) }
                let points=contract.referenceTriangle.map { screen(affine.applying($0)) }
                if let first=points.first {
                    var triangle=Path();triangle.move(to:first);for p in points.dropFirst() { triangle.addLine(to:p) };triangle.closeSubpath()
                    context.stroke(triangle,with:.color(.purple),lineWidth:2)
                    for (i,p) in points.enumerated() { label(i == 0 ? "P′" : "T\(i)",at:.init(x:p.x+10,y:p.y-10),color:.purple) }
                }
            }
        }
    }
}


struct NFSolidSectionInspectionState:Equatable {
    private(set) var showsSection=false
    mutating func reveal(contract:NFSolidSectionContract,phase:NFSpatialLearningPhase)->Bool {
        guard contract.isSupported,phase != .independent else { return false }
        showsSection=true;return true
    }
    mutating func reset() { showsSection=false }
}
enum NFSolidSectionDrawingGeometry {
    typealias G=NFSolidSectionGeometry
    static func solidPaths(_ solid:G.Solid)->[[G.Point]] {
        if solid == .cube {
            return G.Task.corners.enumerated().flatMap { i,p in G.Task.corners.dropFirst(i+1).compactMap { q in
                zip(p.vector,q.vector).filter({$0 != $1}).count == 1 ? [p,q]:nil
            } }
        }
        func circle(_ axis:Int,_ z:Double=0)->[G.Point] {
            (0...64).map { i in
                let angle=Double(i)*2*Double.pi/64,r=solid == .sphere ? 3.0:2.0,x=r*cos(angle),y=r*sin(angle)
                if axis == 0 { return .init(x:x,y:y,z:z) }
                if axis == 1 { return .init(x:x,y:0,z:y) }
                return .init(x:0,y:x,z:y)
            }
        }
        if solid == .sphere { return [circle(0),circle(1),circle(2)] }
        var paths=[circle(0,-3),circle(0,3)]
        for i in 0..<8 { let t=Double(i)*Double.pi/4,x=2*cos(t),y=2*sin(t)
            paths.append([.init(x:x,y:y,z:-3),.init(x:x,y:y,z:3)]) }
        return paths
    }
    static func planePath(_ plane:G.Plane)->[G.Point] {
        let (u,v)=plane.basis,c=plane.center
        return [c-u*3.5-v*3.5,c+u*3.5-v*3.5,c+u*3.5+v*3.5,c-u*3.5+v*3.5,c-u*3.5-v*3.5]
    }
    static func sectionPath(_ task:G.Task)->[G.Point] {
        let boundary=task.boundary
        return boundary.count>2 ? boundary+[boundary[0]]:boundary
    }
    static func project(_ p:G.Point,camera:String)->CGPoint {
        switch camera {
        case "Front":return .init(x:p.x,y:-p.z)
        case "Side":return .init(x:p.y,y:-p.z)
        case "Top":return .init(x:p.x,y:-p.y)
        default:return .init(x:sqrt(0.5)*(p.x+p.y),y:-sqrt(2.0/3.0)*p.z+sqrt(1.0/6.0)*(p.x-p.y))
        }
    }
}
private struct NFSolidSectionStimulusView:View {
    let contract:NFSolidSectionContract
    let phase:NFSpatialLearningPhase
    let prefersReducedMotion:Bool
    @State private var inspection=NFSolidSectionInspectionState()
    @State private var camera="Authored view"
    @State private var native=true
    @State private var generation=0
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    private var showsSection:Bool { phase != .independent && inspection.showsSection }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(contract.text("Original solid and cutting plane","元の立体と切断平面")).font(.headline)
            Menu {
                Button { native=true } label:{ Label("Native 3D",systemImage:native ? "checkmark":"cube") }
                Button { native=false } label:{ Label("Static 2D",systemImage:native ? "square":"checkmark") }
            } label:{ Text(LocalizedStringKey(native ? "Native 3D":"Static 2D")).frame(minWidth:44,minHeight:58).contentShape(Rectangle()) }
                .buttonStyle(.bordered).accessibilityIdentifier("solid-section-rendering-mode")
                .accessibilityValue(Text(LocalizedStringKey(native ? "Native 3D":"Static 2D")))
            if native {
                NFSolidSectionRealityView(contract:contract,camera:camera,showsSection:showsSection,allowsOrbit:!(reducedMotion || prefersReducedMotion))
                    .id("\(camera)-\(generation)-\(showsSection)")
            } else {
                NFSolidSectionDrawing(contract:contract,camera:camera,showsSection:showsSection)
                    .frame(minHeight:300,idealHeight:350).accessibilityHidden(true)
            }
            ViewThatFits(in:.horizontal) { HStack { cameraControls }; VStack(alignment:.leading) { cameraControls } }
            Text(contract.sourceDescription).font(.body.monospaced()).textSelection(.enabled)
                .accessibilityIdentifier("solid-section-original-givens")
            Text(contract.text("The blue wireframe is the original solid. The orange outlined patch lies in the stated infinite plane; its drawing border is not a solid or section boundary. Camera controls change only the view, not the geometry or your answer.","青い線は元の立体です。オレンジの枠は指定された無限の平面の一部を示し、その枠は立体や断面の境界ではありません。カメラ操作は視点だけを変え、幾何の条件や回答は変えません。"))
                .font(.footnote)
            if phase != .independent {
                HStack {
                    Button {
                        if inspection.reveal(contract:contract,phase:phase) { announce(contract.explanation) }
                    } label:{ Text(contract.text("Show worked section","解説用の断面を表示")).frame(minWidth:44,minHeight:58).contentShape(Rectangle()) }
                        .buttonStyle(.bordered).disabled(showsSection).accessibilityIdentifier("solid-section-show-worked")
                    Button { inspection.reset();announce(contract.sourceDescription) } label:{ Text(contract.text("Reset worked section","解説用の断面を元に戻す")).frame(minWidth:44,minHeight:58).contentShape(Rectangle()) }
                        .buttonStyle(.bordered).accessibilityIdentifier("solid-section-reset-worked")
                }
                if showsSection {
                    Text(contract.explanation).accessibilityIdentifier("solid-section-worked-explanation")
                    Text(contract.text("The green computed intersection is a post-response explanation. Your saved answer stays unchanged.","緑の計算された交わりは回答後の解説です。保存済みの回答は変わりません。"))
                        .font(.footnote)
                }
            } else {
                Text(contract.text("The computed section is hidden until your answer is saved.","計算された断面は回答が保存されるまで表示しません。"))
                    .font(.footnote).accessibilityIdentifier("solid-section-independent-policy")
            }
            Text(contract.text("Exact equations are an accessible equivalent for this symbolic geometry practice. They are not a validated substitute for a visual assessment.","この記号による幾何の練習では、正確な式からも同じ条件を読み取れます。視覚的な評価と同等だと検証された代替課題ではありません。"))
                .font(.footnote).foregroundStyle(.secondary)
        }.accessibilityElement(children:.contain).accessibilityIdentifier("solid-section-stimulus")
            .onChange(of:contract){ _,_ in inspection.reset();camera="Authored view";generation+=1 }
            .onChange(of:phase){ _,value in if value == .independent { inspection.reset() } }
    }
    @ViewBuilder private var cameraControls:some View {
        Menu {
            Picker("Camera view",selection:$camera) {
                Text("Authored view").tag("Authored view");Text("Front").tag("Front");Text("Side").tag("Side");Text("Top").tag("Top")
            }
        } label:{ VStack(alignment:.leading){ Text("Camera view").font(.caption);Text(LocalizedStringKey(camera)) }.frame(minWidth:44,minHeight:58).contentShape(Rectangle()) }
            .buttonStyle(.bordered).accessibilityIdentifier("solid-section-camera")
            .accessibilityValue(Text(LocalizedStringKey(camera)))
        Button { camera="Authored view";generation+=1;announce(contract.text("Camera reset to the authored view.","カメラを元の視点に戻しました。")) } label:{ Text("Reset view").frame(minWidth:44,minHeight:58).contentShape(Rectangle()) }
            .buttonStyle(.bordered).accessibilityIdentifier("solid-section-camera-reset")
    }
    private func announce(_ value:String) {
        #if os(iOS)
        UIAccessibility.post(notification:.announcement,argument:value)
        #elseif os(macOS)
        if let window=NSApp.keyWindow { NSAccessibility.post(element:window,notification:.announcementRequested,userInfo:[.announcement:value,.priority:NSAccessibilityPriorityLevel.high.rawValue]) }
        #endif
    }
}
private struct NFSolidSectionDrawing:View {
    let contract:NFSolidSectionContract
    let camera:String
    let showsSection:Bool
    var body:some View {
        Canvas { context,size in
            let scale=min(size.width,size.height)/15
            func point(_ p:NFSolidSectionGeometry.Point)->CGPoint {
                let v=NFSolidSectionDrawingGeometry.project(p,camera:camera)
                return .init(x:size.width/2+v.x*scale,y:size.height/2+v.y*scale)
            }
            func line(_ values:[NFSolidSectionGeometry.Point],color:Color,width:CGFloat,dash:[CGFloat]=[]) {
                guard !values.isEmpty else { return };var path=Path();path.addLines(values.map(point))
                context.stroke(path,with:.color(color),style:.init(lineWidth:width,dash:dash))
            }
            for path in NFSolidSectionDrawingGeometry.solidPaths(contract.task.solid) { line(path,color:.blue,width:1.7) }
            line(NFSolidSectionDrawingGeometry.planePath(contract.task.plane),color:.orange,width:2,dash:[6,4])
            for (label,end) in [("+x",NFSolidSectionGeometry.Point(x:4,y:0,z:0)),("+y",.init(x:0,y:4,z:0)),("+z",.init(x:0,y:0,z:4))] {
                line([.zero,end],color:.secondary,width:1,dash:[3,3]);context.draw(Text(label).font(.caption.bold()),at:point(end))
            }
            if showsSection {
                let section=NFSolidSectionDrawingGeometry.sectionPath(contract.task)
                if section.count == 1,let p=section.first {
                    let v=point(p);context.fill(Path(ellipseIn:.init(x:v.x-4,y:v.y-4,width:8,height:8)),with:.color(.green))
                } else { line(section,color:.green,width:4) }
            }
        }
    }
}
private struct NFSolidSectionRealityView:View {
    let contract:NFSolidSectionContract
    let camera:String
    let showsSection:Bool
    let allowsOrbit:Bool
    var body:some View {
        RealityView { content in
            content.camera = .virtual
            let root=NFSpatialRealitySceneFactory.makeSectionScene(contract:contract,showsSection:showsSection)
            if camera == "Authored view" { root.orientation=simd_quatf(angle:Float(atan(1/sqrt(2.0))),axis:[1,0,0])*simd_quatf(angle:-.pi/4,axis:[0,1,0]) }
            if camera == "Side" { root.orientation=simd_quatf(angle:-.pi/2,axis:[0,1,0]) }
            if camera == "Top" { root.orientation=simd_quatf(angle:.pi/2,axis:[1,0,0]) }
            content.add(root);content.cameraTarget=root
        } placeholder:{ ProgressView("Preparing 3D model") }
            .realityViewCameraControls(allowsOrbit ? .orbit:.none)
            .frame(minHeight:300,idealHeight:350).accessibilityHidden(true)
    }
}
extension NFSpatialRealitySceneFactory {
    static func makeSectionScene(contract:NFSolidSectionContract,showsSection:Bool)->Entity {
        let root=Entity();root.name="nf.solid-section"
        guard contract.isSupported else { return root }
        func world(_ p:NFSolidSectionGeometry.Point)->SIMD3<Float> { [Float(p.x)*0.15,Float(p.z)*0.15,-Float(p.y)*0.15] }
        func add(_ path:[NFSolidSectionGeometry.Point],name:String,color:NFSpatialPlatformColor,radius:Float) {
            for index in path.indices.dropFirst() {
                let a=world(path[index-1]),b=world(path[index]),delta=b-a,distance=simd_length(delta)
                guard distance>0 else { continue }
                let entity=model(name:name+".\(index)",mesh:.generateCylinder(height:distance,radius:radius),color:color,position:(a+b)/2)
                entity.orientation=simd_quatf(from:[0,1,0],to:delta/distance);root.addChild(entity)
            }
        }
        for (index,path) in NFSolidSectionDrawingGeometry.solidPaths(contract.task.solid).enumerated() { add(path,name:"solid.edge.\(index)",color:.systemBlue,radius:0.004) }
        add(NFSolidSectionDrawingGeometry.planePath(contract.task.plane),name:"given.plane",color:.systemOrange,radius:0.006)
        if showsSection {
            let path=NFSolidSectionDrawingGeometry.sectionPath(contract.task)
            if path.count == 1,let p=path.first { root.addChild(model(name:"worked.contact",mesh:.generateSphere(radius:0.025),color:.systemGreen,position:world(p))) }
            else { add(path,name:"worked.section",color:.systemGreen,radius:0.011) }
        }
        for (label,end) in [("+x",NFSolidSectionGeometry.Point(x:4,y:0,z:0)),("+y",.init(x:0,y:4,z:0)),("+z",.init(x:0,y:0,z:4))] {
            add([.zero,end],name:"axis."+label,color:.nfSpatialLabel,radius:0.002)
            root.addChild(model(name:"axis.label."+label,mesh:.generateText(label,extrusionDepth:0.001,font:.systemFont(ofSize:0.055)),color:.nfSpatialLabel,position:world(end)))
        }
        return root
    }
}


struct NFNetFoldingInspection:Equatable {
    enum State:String {case given,flat,completed}
    private(set) var state:State = .given
    mutating func select(_ value:State,contract:NFNetFoldingContract,phase:NFSpatialLearningPhase)->Bool {
        guard phase != .independent,contract.isSupported,(value != .completed || contract.task.validNet) else{return false}
        state=value;return true
    }
    mutating func reset(){state = .given}
    func frames(contract:NFNetFoldingContract,phase:NFSpatialLearningPhase)->[NFNetFoldingGeometry.Frame] {
        guard contract.isSupported else{return []}
        switch phase == .independent ? .given:state {
        case .given:return contract.task.originalFrames ?? []
        case .flat:return NFNetFoldingGeometry.Task.frames(contract.task.layout,folded:[]) ?? []
        case .completed:return contract.task.completedFrames ?? []
        }
    }
}
private struct NFNetFoldingStimulusView:View {
    let contract:NFNetFoldingContract
    let phase:NFSpatialLearningPhase
    let prefersReducedMotion:Bool
    @State private var inspection=NFNetFoldingInspection()
    @State private var camera="Authored view"
    @State private var native=true
    @State private var generation=0
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    private var frames:[NFNetFoldingGeometry.Frame] {inspection.frames(contract:contract,phase:phase)}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(contract.text("Original crease pattern and face arrows","元の折り目と面の矢印")).font(.headline)
            NFNetCreasePattern(contract:contract).frame(minHeight:240).accessibilityHidden(true)
            Text(contract.sourceDescription).textSelection(.enabled).accessibilityIdentifier("net-folding-givens")
            Menu {
                Button {native=true} label:{Label("Native 3D",systemImage:native ? "checkmark":"cube")}
                Button {native=false} label:{Label("Static 2D",systemImage:native ? "square":"checkmark")}
            } label:{Text(LocalizedStringKey(native ? "Native 3D":"Static 2D")).frame(minWidth:44,minHeight:58).contentShape(Rectangle())}
                .accessibilityIdentifier("net-folding-rendering-mode")
                .accessibilityValue(native ? "Native 3D" : "Static 2D")
                .buttonStyle(.bordered)
            ZStack {
                if native {
                    RealityView { content in
                        let root=NFSpatialRealitySceneFactory.makeNetFoldingScene(frames:frames)
                        orient(root);content.add(root);content.cameraTarget=root
                    } placeholder:{ProgressView("Preparing 3D model")}
                        .realityViewCameraControls((reducedMotion || prefersReducedMotion) ? .none:.orbit)
                        .id("\(camera)-\(generation)-\(inspection.state.rawValue)")
                        .accessibilityHidden(true)
                } else { NFNetFoldedProjection(frames:frames,camera:camera).accessibilityHidden(true) }
            }.frame(minHeight:300)
                .accessibilityElement(children:.ignore).accessibilityAddTraits(.isImage)
                .accessibilityLabel(Text(contract.text("Net model","展開図のモデル")))
                .accessibilityValue(Text(phase != .independent && inspection.state == .completed
                    ? contract.explanation : contract.sourceDescription))
                .accessibilityIdentifier("net-folding-model")
            ViewThatFits(in:.horizontal){HStack{cameraControls};VStack(alignment:.leading){cameraControls}}
            Text(contract.text("Camera controls never fold a hinge or change the answer. Blue face labels and upward arrows belong to the original printed squares; the fixed anchor does not move during folding.","カメラ操作で折り目や回答は変わりません。青い面の文字と上向き矢印は元の正方形に印刷されたもので、折る間も基準面は固定されます。"))
                .font(.footnote)
            if phase != .independent {
                ViewThatFits(in:.horizontal){HStack{foldControls};VStack(alignment:.leading){foldControls}}
                if inspection.state == .completed {Text(contract.explanation).accessibilityIdentifier("net-folding-worked-frames")}
                if !contract.task.validNet {Text(contract.explanation).accessibilityIdentifier("net-folding-invalid-proposal")}
            } else {
                Text(contract.text("Only the stated given fold is shown. Computed Fold and Unfold demonstrations open after saving your answer.","表示するのは与えられた折り状態だけです。計算された折る・開く操作は回答の保存後に使えます。"))
                    .font(.footnote).accessibilityIdentifier("net-folding-independent-policy")
            }
            Text(contract.text("The square coordinates, hinge rules and printed-arrow convention provide the same symbolic givens. This is ordinary practice, not a validated replacement for a visual assessment.","正方形の座標、折り目の規則、矢印の約束から同じ記号的条件を読み取れます。これは通常の練習であり、視覚的な評価の代替として検証されたものではありません。"))
                .font(.footnote).foregroundStyle(.secondary)
        }.accessibilityElement(children:.contain).accessibilityIdentifier("net-folding-stimulus")
            .onChange(of:contract){_,_ in inspection.reset();camera="Authored view";generation+=1}
            .onChange(of:phase){_,value in if value == .independent {inspection.reset();generation+=1}}
    }
    @ViewBuilder private var cameraControls:some View {
        Menu {Picker("Camera view",selection:$camera){ForEach(["Authored view","Front","Side","Top"],id:\.self){Text(LocalizedStringKey($0)).tag($0)}}}
            label:{VStack(alignment:.leading){Text("Camera view").font(.caption);Text(LocalizedStringKey(camera))}.frame(minWidth:44,minHeight:58).contentShape(Rectangle())}
            .accessibilityIdentifier("net-folding-camera")
            .accessibilityValue(LocalizedStringKey(camera))
            .buttonStyle(.bordered)
        Button {camera="Authored view";generation+=1;announce(contract.text("Camera reset to the original view.","カメラを元の視点に戻しました。"))}
            label:{Text("Reset view").frame(minWidth:44,minHeight:58).contentShape(Rectangle())}
            .buttonStyle(.bordered).accessibilityIdentifier("net-folding-camera-reset")
    }
    @ViewBuilder private var foldControls:some View {
        Button {select(.completed)} label:{Text(contract.text("Complete fold","折りを完成させる")).frame(minWidth:44,minHeight:58).contentShape(Rectangle())}
            .buttonStyle(.bordered).disabled(!contract.task.validNet || inspection.state == .completed).accessibilityIdentifier("net-folding-complete")
        Button {select(.flat)} label:{Text(contract.text("Unfold every hinge","すべての折り目を開く")).frame(minWidth:44,minHeight:58).contentShape(Rectangle())}
            .buttonStyle(.bordered).accessibilityIdentifier("net-folding-unfold")
        Button {select(.given)} label:{Text(contract.text("Restore given fold","与えられた折り状態に戻す")).frame(minWidth:44,minHeight:58).contentShape(Rectangle())}
            .buttonStyle(.bordered).accessibilityIdentifier("net-folding-reset")
    }
    private func select(_ state:NFNetFoldingInspection.State) {
        guard inspection.select(state,contract:contract,phase:phase) else{return};generation+=1
        announce(state == .completed ? contract.explanation:state == .flat ? contract.text("All hinges are flat; the face labels and arrows are unchanged.","すべての折り目を開きました。面の文字と矢印は変わりません。"):contract.sourceDescription)
    }
    private func orient(_ entity:Entity){entity.orientation=NFNetFoldingProjection.orientation(camera:camera)}
    private func announce(_ value:String) {
        #if os(iOS)
        UIAccessibility.post(notification:.announcement,argument:value)
        #elseif os(macOS)
        if let window = NSApp?.keyWindow {
            NSAccessibility.post(element:window,notification:.announcementRequested,userInfo:[.announcement:value,.priority:NSAccessibilityPriorityLevel.medium.rawValue])
        }
        #endif
    }
}
enum NFNetFoldingProjection {
    static func orientation(camera:String)->simd_quatf {
        switch camera {
        case "Side":simd_quatf(angle:-.pi/2,axis:[0,1,0])
        case "Top":simd_quatf(angle:.pi/2,axis:[1,0,0])
        case "Front":simd_quatf(angle:0,axis:[0,1,0])
        default:simd_quatf(angle:.pi/6,axis:[1,0,0])*simd_quatf(angle:-.pi/6,axis:[0,1,0])
        }
    }
    static func project(_ v:NFNetFoldingGeometry.Vector,camera:String)->CGPoint {
        let p=orientation(camera:camera).act(SIMD3<Float>(Float(v.x)/2,Float(v.y)/2,Float(v.z)/2));return .init(x:Double(p.x),y:-Double(p.y))
    }
}
private struct NFNetCreasePattern:View {
    let contract:NFNetFoldingContract
    var body:some View {Canvas { context,size in
        let cells=contract.task.layout.cells,w=CGFloat((cells.map(\.x).max() ?? 0)+1),h=CGFloat((cells.map(\.y).max() ?? 0)+1)
        let unit=min((size.width-24)/w,(size.height-24)/h),left=(size.width-w*unit)/2,top=(size.height-h*unit)/2
        for c in cells {
            let rect=CGRect(x:left+CGFloat(c.x)*unit,y:top+(h-1-CGFloat(c.y))*unit,width:unit,height:unit)
            context.fill(Path(rect),with:.color(Color.blue.opacity(0.12)))
            context.stroke(Path(rect),with:.color(Color.primary),lineWidth:1.5)
            if c.label == contract.task.givenFoldedLeaf { context.stroke(Path(rect.insetBy(dx:3,dy:3)),with:.color(.orange),style:.init(lineWidth:3,dash:[5,3])) }
            context.draw(Text(c.label+" ↑").font(.system(size:max(15,min(24,unit/3)),weight:.bold)),at:.init(x:rect.midX,y:rect.midY))
        }
        for a in cells {for b in cells where a.label<b.label && abs(a.x-b.x)+abs(a.y-b.y)==1 {
            let x:CGFloat,y:CGFloat,start:CGPoint,end:CGPoint
            if a.x != b.x {
                x=left+CGFloat(max(a.x,b.x))*unit;y=top+(h-1-CGFloat(a.y))*unit
                start = .init(x:x,y:y);end = .init(x:x,y:y+unit)
            } else {
                x=left+CGFloat(a.x)*unit;y=top+(h-CGFloat(max(a.y,b.y)))*unit
                start = .init(x:x,y:y);end = .init(x:x+unit,y:y)
            }
            var hinge=Path();hinge.move(to:start);hinge.addLine(to:end)
            context.stroke(hinge,with:.color(.orange),style:.init(lineWidth:3,dash:[6,3]))
        }}
    }}
}
private struct NFNetFoldedProjection:View {
    let frames:[NFNetFoldingGeometry.Frame],camera:String
    var body:some View {Canvas {context,size in
        let points=frames.flatMap(\.corners2).map{NFNetFoldingProjection.project($0,camera:camera)}
        let minX=points.map(\.x).min() ?? 0,maxX=points.map(\.x).max() ?? 1,minY=points.map(\.y).min() ?? 0,maxY=points.map(\.y).max() ?? 1
        let scale=min((size.width-40)/max(1,maxX-minX),(size.height-40)/max(1,maxY-minY))
        func map(_ p:NFNetFoldingGeometry.Vector)->CGPoint{let q=NFNetFoldingProjection.project(p,camera:camera);return .init(x:size.width/2+(q.x-(minX+maxX)/2)*scale,y:size.height/2+(q.y-(minY+maxY)/2)*scale)}
        for (name,v) in [("+x",NFNetFoldingGeometry.Vector.xAxis),("+y",.yAxis),("+z",.zAxis)] {
            var axis=Path();axis.move(to:map(.zero));axis.addLine(to:map(v*3));context.stroke(axis,with:.color(Color.secondary),lineWidth:1)
            context.draw(Text(name).font(.caption.bold()),at:map(v*3))
        }
        for frame in frames {
            let corners=frame.corners2.map(map);var path=Path();path.addLines(corners);path.closeSubpath()
            context.stroke(path,with:.color(.blue),lineWidth:2)
            context.draw(Text(frame.label).font(.headline),at:map(frame.center2))
            var arrow=Path();arrow.move(to:map(frame.center2));arrow.addLine(to:map(frame.center2+frame.up));context.stroke(arrow,with:.color(.orange),lineWidth:3)
            context.fill(Path(ellipseIn:CGRect(x:map(frame.center2+frame.up).x-3,y:map(frame.center2+frame.up).y-3,width:6,height:6)),with:.color(.orange))
        }
    }}
}
extension NFSpatialRealitySceneFactory {
    static func makeNetFoldingScene(frames:[NFNetFoldingGeometry.Frame])->Entity {
        let root=Entity();root.name="nf.net-folding"
        func vector(_ v:NFNetFoldingGeometry.Vector)->SIMD3<Float>{[Float(v.x),Float(v.y),Float(v.z)]}
        for frame in frames {
            let panel=model(name:"net.face."+frame.label,mesh:.generateBox(size:[0.98,0.98,0.016]),color:.systemBlue,position:vector(frame.center2)/2)
            panel.orientation=simd_quatf(simd_float3x3(columns:(vector(frame.right),vector(frame.up),vector(frame.normal))))
            let label=model(name:"net.arrow."+frame.label,mesh:.generateText(frame.label+" ↑",extrusionDepth:0.002,font:.systemFont(ofSize:0.20)),color:.white,position:[-0.24,-0.06,0.02])
            panel.addChild(label);root.addChild(panel)
        }
        let axes=Entity();axes.name="net.fixed-axes"
        for (name,v) in [("+x",NFNetFoldingGeometry.Vector.xAxis),("+y",.yAxis),("+z",.zAxis)] {
            let direction=vector(v)
            let shaft=model(name:"net.axis."+name,mesh:.generateCylinder(height:1.5,radius:0.008),color:.nfSpatialLabel,position:direction*0.75)
            shaft.orientation=simd_quatf(from:[0,1,0],to:direction);axes.addChild(shaft)
            axes.addChild(model(name:"net.axis-label."+name,mesh:.generateText(name,extrusionDepth:0.002,font:.systemFont(ofSize:0.16)),color:.nfSpatialLabel,position:direction*1.5))
        }
        root.addChild(axes)
        return root
    }
}


struct NFCoordinateReasoningDrawingPlan: Equatable, Sendable {
    let originalPoints: [NFSpatialPoint]
    let workedPoints: [NFSpatialPoint]?
}
struct NFCoordinateReasoningInspection: Equatable, Sendable {
    private(set) var showsWorked = false
    mutating func reveal(contract:NFCoordinateReasoningContract,phase:NFSpatialLearningPhase)->Bool {
        guard contract.isSupported,phase != .independent else { return false }
        showsWorked=true;return true
    }
    mutating func reset() { showsWorked=false }
    func isVisible(contract:NFCoordinateReasoningContract,phase:NFSpatialLearningPhase)->Bool { contract.isSupported && phase != .independent && showsWorked }
    func drawingPlan(contract:NFCoordinateReasoningContract,phase:NFSpatialLearningPhase)->NFCoordinateReasoningDrawingPlan {
        .init(originalPoints:contract.publicPoints,
              workedPoints:isVisible(contract:contract,phase:phase) ? points(contract:contract,phase:phase):nil)
    }
    private func points(contract:NFCoordinateReasoningContract,phase:NFSpatialLearningPhase)->[NFSpatialPoint] {
        var result=contract.publicPoints
        guard isVisible(contract:contract,phase:phase) else { return result }
        switch contract.task.query {
        case .inverse:
            let point=contract.task.originals[0];result.append(.init(label:"P",x:Double(point.x),y:Double(point.y),z:nil))
        case .inferAffine: break
        case .orientationFixed:
            result += contract.task.pairs.enumerated().map { .init(label:["A′","B′","C′"][$0.offset],x:Double($0.element.target.x),y:Double($0.element.target.y),z:nil) }
        }
        return result
    }
}
struct NFCoordinateReasoningStimulusView: View {
    let contract:NFCoordinateReasoningContract
    let phase:NFSpatialLearningPhase
    @State private var inspection=NFCoordinateReasoningInspection()
    private var drawingPlan:NFCoordinateReasoningDrawingPlan { inspection.drawingPlan(contract:contract,phase:phase) }
    private var visible:Bool { inspection.isVisible(contract:contract,phase:phase) }
    var body:some View {
        if contract.isSupported {
            VStack(alignment:.leading,spacing:14) {
                Text(contract.text("Original transformation givens","元の変換の条件")).font(.headline)
                NFCoordinateReasoningDrawing(contract:contract,points:drawingPlan.originalPoints)
                    .frame(minHeight:280,idealHeight:340).accessibilityHidden(true)
                Text(contract.sourceDescription).accessibilityIdentifier("coordinate-reasoning-original")
                if phase != .independent {
                    HStack {
                        Button {
                            if inspection.reveal(contract:contract,phase:phase) { announce(contract.explanation) }
                        } label: {
                            Text(contract.text("Show worked map","解説用の変換を表示"))
                                .frame(minWidth:44,minHeight:58).contentShape(Rectangle())
                        }.buttonStyle(.bordered).accessibilityIdentifier("coordinate-reasoning-show")
                        Button { inspection.reset();announce(contract.sourceDescription) } label: {
                            Text(contract.text("Reset worked copy","解説用コピーを元に戻す"))
                                .frame(minWidth:44,minHeight:58).contentShape(Rectangle())
                        }.buttonStyle(.bordered).accessibilityIdentifier("coordinate-reasoning-reset")
                    }
                    if visible,let workedPoints=drawingPlan.workedPoints {
                        NFCoordinateReasoningDrawing(contract:contract,points:workedPoints)
                            .frame(minHeight:280,idealHeight:340).accessibilityHidden(true)
                        Text(contract.explanation).accessibilityIdentifier("coordinate-reasoning-worked")
                        Text(workedPoints.map { "\($0.label) = (\(Int($0.x)), \(Int($0.y)))" }.joined(separator:"; "))
                            .font(.body.monospaced()).accessibilityIdentifier("coordinate-reasoning-worked-points")
                    }
                } else {
                    Text(contract.text("The givens stay fixed while you answer. A separate worked copy is available only after saving.","回答中は条件を固定して表示します。別の解説用コピーは保存後に利用できます。"))
                        .font(.footnote)
                }
            }.accessibilityElement(children:.contain).accessibilityIdentifier("coordinate-reasoning-stimulus")
                .onChange(of:contract) { _,_ in inspection.reset() }
                .onChange(of:phase) { _,value in if value == .independent { inspection.reset() } }
        }
    }
    private func announce(_ text:String) {
        #if os(iOS)
        UIAccessibility.post(notification:.announcement,argument:text)
        #elseif os(macOS)
        if let window=NSApp?.keyWindow {
            NSAccessibility.post(element:window,notification:.announcementRequested,
                userInfo:[.announcement:text,.priority:NSAccessibilityPriorityLevel.high.rawValue])
        }
        #endif
    }
}
private struct NFCoordinateReasoningDrawing: View {
    let contract:NFCoordinateReasoningContract
    let points:[NFSpatialPoint]
    var body:some View {
        Canvas { context,size in
            let extent=max(6,Int(ceil(points.flatMap{[abs($0.x),abs($0.y)]}.max() ?? 4))+2)
            let side=max(1,min(size.width-64,size.height-56)),unit=side/CGFloat(2*extent)
            let left=(size.width-side)/2,top=(size.height-side)/2
            func screen(_ x:Double,_ y:Double)->CGPoint { .init(x:left+CGFloat(x+Double(extent))*unit,y:top+CGFloat(Double(extent)-y)*unit) }
            for i in -extent...extent {
                var grid=Path();grid.move(to:screen(Double(i),Double(-extent)));grid.addLine(to:screen(Double(i),Double(extent)))
                grid.move(to:screen(Double(-extent),Double(i)));grid.addLine(to:screen(Double(extent),Double(i)))
                context.stroke(grid,with:.color(.secondary.opacity(i == 0 ? 0.8:0.15)),lineWidth:i == 0 ? 1.5:0.6)
                if i != 0 && i % max(1,extent/4) == 0 {
                    let x=screen(Double(i),0),y=screen(0,Double(i))
                    context.draw(Text(String(i)).font(.caption2),at:.init(x:x.x,y:x.y+10))
                    context.draw(Text(String(i)).font(.caption2),at:.init(x:y.x-11,y:y.y))
                }
            }
            // Centers and mirror lines are public givens for inverse and
            // classification tasks. Inference tasks must never render their
            // private generating recipe before or after the correspondence plot.
            if contract.task.query != .inferAffine {
                for (index,operation) in contract.task.operations.enumerated() {
                    switch operation {
                    case let .rotate(center,_):
                        let at=screen(Double(center.x),Double(center.y))
                        var mark=Path();mark.move(to:.init(x:at.x-5,y:at.y-5));mark.addLine(to:.init(x:at.x+5,y:at.y+5))
                        mark.move(to:.init(x:at.x-5,y:at.y+5));mark.addLine(to:.init(x:at.x+5,y:at.y-5))
                        context.stroke(mark,with:.color(.orange),lineWidth:2)
                        let centerNames=contract.task.operations.enumerated().compactMap { offset, candidate -> String? in
                            guard case let .rotate(other,_) = candidate,other == center else { return nil }
                            return "C\(offset+1)"
                        }
                        if centerNames.first == "C\(index+1)" {
                            // Keep center labels below the x-axis tick labels,
                            // and combine coincident centers instead of overprinting.
                            context.draw(Text(centerNames.joined(separator:"/")).font(.caption2),
                                at:.init(x:at.x+8,y:at.y+18),anchor:.topLeading)
                        }
                    case let .reflect(line,k):
                        let ends:(CGPoint,CGPoint)
                        switch line {
                        case .vertical:ends=(screen(Double(k),Double(-extent)),screen(Double(k),Double(extent)))
                        case .horizontal:ends=(screen(Double(-extent),Double(k)),screen(Double(extent),Double(k)))
                        case .risingDiagonal:ends=(screen(Double(-extent),Double(-extent)),screen(Double(extent),Double(extent)))
                        case .fallingDiagonal:ends=(screen(Double(-extent),Double(extent)),screen(Double(extent),Double(-extent)))
                        }
                        var mirror=Path();mirror.move(to:ends.0);mirror.addLine(to:ends.1)
                        context.stroke(mirror,with:.color(.orange),style:.init(lineWidth:1.6,dash:[5,3]))
                    case .translate:break
                    }
                }
            }
            if contract.task.query != .inverse {
                for names in [["A","B","C"],["A′","B′","C′"]] {
                    let vertices=names.compactMap { name in points.first{$0.label==name} }
                    if vertices.count == 3 {
                        var triangle=Path();triangle.move(to:screen(vertices[0].x,vertices[0].y))
                        for p in vertices.dropFirst(){triangle.addLine(to:screen(p.x,p.y))};triangle.closeSubpath()
                        context.stroke(triangle,with:.color(names[0].contains("′") ? .purple:.blue),lineWidth:2)
                    }
                }
            }
            let groups=Dictionary(grouping:points,by:{ "\($0.x),\($0.y)" })
            for key in groups.keys.sorted() {
                guard let values=groups[key],let point=values.first else { continue }
                let at=screen(point.x,point.y),label=values.map(\.label).joined(separator:"/"),color:Color = values.contains{$0.label.contains("′") || $0.label == "P"} ? .purple:.blue
                context.fill(Path(ellipseIn:.init(x:at.x-4,y:at.y-4,width:8,height:8)),with:.color(color))
                context.draw(Text(label).font(.caption.bold()).foregroundStyle(color),at:.init(x:at.x+14,y:at.y-10))
            }
            context.draw(Text(contract.text("x (grid units)","x（格子単位）")).font(.caption),at:.init(x:left+side/2,y:top+side+19))
            context.draw(Text(contract.text("y (grid units)","y（格子単位）")).font(.caption),at:.init(x:left+side/2,y:top-14))
        }
    }
}

struct NFSpatialAssemblyInspection: Equatable, Sendable {
    private(set) var showsWorked = false
    mutating func reveal(contract:NFSpatialAssemblyContract,phase:NFSpatialLearningPhase)->Bool {
        guard contract.isSupported,phase != .independent else{return false};showsWorked=true;return true
    }
    mutating func reset(){showsWorked=false}
    func workedCells(contract:NFSpatialAssemblyContract,index:Int,phase:NFSpatialLearningPhase)->[NFSpatialAssemblyGeometry.Cell]? {
        guard contract.isSupported,phase != .independent,showsWorked,index>=0,index<contract.task.candidateCount else{return nil}
        switch contract.task {
        case let .orientation(v):return v.matchingRotation(for:index)?.apply(v.source) ?? v.candidates[index]
        case let .reconstruction(v):return NFSpatialAssemblyGeometry.cells(heights:v.candidates[index])
        }
    }
}
struct NFSpatialAssemblyStimulusView:View {
    let contract:NFSpatialAssemblyContract
    let phase:NFSpatialLearningPhase
    var prefersReducedMotion=false
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @State private var inspection=NFSpatialAssemblyInspection()
    @State private var camera="Authored view"
    @State private var native=false
    @State private var resetID=0
    private var reducesMotion:Bool{systemReducedMotion || prefersReducedMotion}
    var body:some View {
        if contract.isSupported {
            VStack(alignment:.leading,spacing:16) {
                Text(contract.sourceDescription).accessibilityIdentifier("spatial-assembly-original")
                switch contract.task {
                case let .orientation(v):
                    sourceObject(v.source)
                    ForEach(v.candidates.indices,id:\.self){i in
                        VStack(alignment:.leading,spacing:8){
                            Text(contract.text("Candidate \(NFSpatialAssemblyContract.choiceID(i))","候補\(NFSpatialAssemblyContract.choiceID(i))")).font(.headline)
                            pairedViews(v.shown[i],prefix:"spatial-assembly-candidate-\(i)")
                        }.padding(12).background(.thinMaterial,in:RoundedRectangle(cornerRadius:12))
                    }
                case let .reconstruction(v):
                    let top=v.constraints.top.enumerated().filter{$0.element}.map{NFSpatialAssemblyGeometry.Square(x:$0.offset%2,y:$0.offset/2)}
                    projection(title:contract.text("Supplied top footprint","与えられた上面の占有形"),squares:top,x:"x",y:"y",id:"spatial-assembly-top")
                    pairedViews(.init(front:v.constraints.front.enumerated().flatMap{i,h in (0..<h).map{.init(x:i,y:$0)}},
                                      side:v.constraints.side.enumerated().flatMap{i,h in (0..<h).map{.init(x:i,y:$0)}}),prefix:"spatial-assembly-givens")
                    ForEach(v.candidates.indices,id:\.self){i in
                        VStack(alignment:.leading,spacing:8){
                            Text(contract.text("Candidate \(NFSpatialAssemblyContract.choiceID(i))","候補\(NFSpatialAssemblyContract.choiceID(i))")).font(.headline)
                            NFSpatialAssemblySolidDrawing(cells:NFSpatialAssemblyGeometry.cells(heights:v.candidates[i]),camera:"Authored view")
                                .frame(height:190)
                                .accessibilityElement(children:.ignore).accessibilityLabel(contract.heightsText(v.candidates[i]))
                                .accessibilityIdentifier("spatial-assembly-candidate-model-\(i)")
                            Text(contract.heightsText(v.candidates[i])).font(.body.monospaced())
                                .accessibilityIdentifier("spatial-assembly-candidate-heights-\(i)")
                        }.padding(12).background(.thinMaterial,in:RoundedRectangle(cornerRadius:12))
                    }
                }
                if phase != .independent {
                    ViewThatFits(in:.horizontal){HStack{workedControls};VStack(alignment:.leading){workedControls}}
                    if inspection.showsWorked {
                        Text(contract.explanation).accessibilityIdentifier("spatial-assembly-worked")
                        ForEach(0..<contract.task.candidateCount,id:\.self){i in
                            if let cells=inspection.workedCells(contract:contract,index:i,phase:phase) {
                                VStack(alignment:.leading,spacing:8){
                                    Text(contract.text("Worked copy for candidate \(NFSpatialAssemblyContract.choiceID(i))","候補\(NFSpatialAssemblyContract.choiceID(i))の解説用コピー")).font(.headline)
                                    NFSpatialAssemblySolidDrawing(cells:cells,camera:"Authored view").frame(height:190)
                                        .accessibilityElement(children:.ignore).accessibilityLabel(contract.cellsText(cells))
                                        .accessibilityIdentifier("spatial-assembly-worked-model-\(i)")
                                    Text(contract.cellsText(cells)).font(.body.monospaced())
                                        .accessibilityIdentifier("spatial-assembly-worked-cells-\(i)")
                                }
                            }
                        }
                    }
                }
            }.accessibilityElement(children:.contain).accessibilityIdentifier("spatial-assembly-stimulus")
                .onChange(of:contract){_,_ in inspection.reset();camera="Authored view";resetID+=1}
                .onChange(of:phase){_,v in if v == .independent{inspection.reset()}}
        }
    }
    @ViewBuilder private var workedControls:some View {
        Button{if inspection.reveal(contract:contract,phase:phase){AccessibilityNotification.Announcement(contract.explanation).post()}}label:{
            Text(contract.text("Show worked reconstructions","解説用の再構成を表示")).frame(minWidth:44,minHeight:58).contentShape(Rectangle())
        }.buttonStyle(.bordered).accessibilityIdentifier("spatial-assembly-show")
        Button{inspection.reset();AccessibilityNotification.Announcement(contract.sourceDescription).post()}label:{
            Text(contract.text("Reset worked copies","解説用コピーを元に戻す")).frame(minWidth:44,minHeight:58).contentShape(Rectangle())
        }.buttonStyle(.bordered).accessibilityIdentifier("spatial-assembly-reset")
    }
    private func sourceObject(_ cells:[NFSpatialAssemblyGeometry.Cell])->some View {
        VStack(alignment:.leading,spacing:10){
            Text(contract.text("Original solid — complete givens","元の立体 — 完全な条件")).font(.headline)
            Group { if native {
                NFSpatialAssemblyRealityView(cells:cells,camera:camera,allowsOrbit:!reducesMotion)
                    .id("\(camera)-\(resetID)")
            }else{NFSpatialAssemblySolidDrawing(cells:cells,camera:camera).frame(height:250)} }
                .accessibilityElement(children:.ignore).accessibilityLabel(contract.cellsText(cells))
                .accessibilityIdentifier("spatial-assembly-source-model")
            Text(contract.text("Camera controls show the fully specified original solid only. Candidate views stay fixed; no answer transformation is performed.","カメラ操作は完全に指定された元の立体だけを表示します。候補の図は固定され、解答となる変換は実行しません。"))
                .font(.footnote)
            ViewThatFits(in:.horizontal){HStack{cameraControls};VStack(alignment:.leading){cameraControls}}
        }
    }
    @ViewBuilder private var cameraControls:some View {
        Menu{
            Button("Authored view"){camera="Authored view"}
            Button("Front"){camera="Front"};Button("Side"){camera="Side"};Button("Top"){camera="Top"}
        }label:{Text(contract.text("Reference camera: ","元の立体のカメラ：")+NFAppLocalization.localizedCatalogValue(camera,locale:Locale(identifier:contract.localeIdentifier)))
            .frame(minWidth:44,minHeight:58).contentShape(Rectangle())}
            .buttonStyle(.bordered).accessibilityIdentifier("spatial-assembly-camera")
        Button{native.toggle()}label:{Text(native ? contract.text("Static 2D","静的な2D表示"):contract.text("Interactive 3D","操作できる3D表示")).frame(minWidth:44,minHeight:58).contentShape(Rectangle())}
            .buttonStyle(.bordered).accessibilityIdentifier("spatial-assembly-render-mode")
        Button{camera="Authored view";resetID+=1;AccessibilityNotification.Announcement(contract.sourceDescription).post()}label:{
            Text("Reset view").frame(minWidth:44,minHeight:58).contentShape(Rectangle())
        }.buttonStyle(.bordered).accessibilityIdentifier("spatial-assembly-reset-view")
    }
    private func pairedViews(_ views:NFSpatialAssemblyGeometry.Views,prefix:String)->some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:220))],spacing:12){
            projection(title:contract.text("Front view","正面図"),squares:views.front,x:"x",y:"z",id:prefix+"-front")
            projection(title:contract.text("Side view","側面図"),squares:views.side,x:"y",y:"z",id:prefix+"-side")
        }
    }
    private func projection(title:String,squares:[NFSpatialAssemblyGeometry.Square],x:String,y:String,id:String)->some View {
        VStack(alignment:.leading,spacing:6){
            Text(title).font(.subheadline.bold())
            NFSpatialPlanDrawing(squares:squares,xLabel:x,yLabel:y).frame(height:175)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(title+". "+contract.text("Filled squares (\(x),\(y)): ","塗られたマス (\(x),\(y))：")+contract.squaresText(squares))
                .accessibilityIdentifier(id+"-model")
            Text(contract.text("Filled squares (\(x),\(y)): ","塗られたマス (\(x),\(y))：")+contract.squaresText(squares))
                .font(.body.monospaced()).accessibilityIdentifier(id)
        }.accessibilityElement(children:.contain)
    }
}
private struct NFSpatialAssemblySolidDrawing:View {
    let cells:[NFSpatialAssemblyGeometry.Cell]
    let camera:String
    var body:some View {
        Canvas{context,size in
            guard NFSpatialAssemblyGeometry.permits(cells) else{return}
            let extent=Double(max(cells.map(\.x).max() ?? 0,max(cells.map(\.y).max() ?? 0,cells.map(\.z).max() ?? 0))+1)
            let scale=min(size.width/(CGFloat(extent)*2.8),size.height/(CGFloat(extent)*2.3))
            let center=SIMD3<Double>(extent/2,extent/2,-extent/2)
            func world(_ c:NFSpatialAssemblyGeometry.Cell)->SIMD3<Double>{[Double(c.x)+0.5,Double(c.z)+0.5,-Double(c.y)-0.5]}
            func screen(_ v:SIMD3<Double>)->CGPoint{
                let p=NFSpatialStructureDrawingGeometry.project(v-center,camera:camera)
                return .init(x:size.width/2+CGFloat(p.x)*scale,y:size.height/2+CGFloat(p.y)*scale)
            }
            let occupied=Set(cells)
            func depth(_ c:NFSpatialAssemblyGeometry.Cell)->Double{let p=world(c);switch camera{case "Front":return p.z;case "Side":return p.x;case "Top":return p.y;default:return p.x+p.y+p.z}}
            for cell in cells.sorted(by:{depth($0)==depth($1) ? $0<$1:depth($0)<depth($1)}){
                let c=world(cell)
                for frame in NFSpatialStructureDrawingGeometry.frames where NFSpatialStructureDrawingGeometry.visible(frame.normal,camera:camera){
                    let neighbor=NFSpatialAssemblyGeometry.Cell(x:cell.x+Int(frame.normal.x),y:cell.y-Int(frame.normal.z),z:cell.z+Int(frame.normal.y))
                    guard !occupied.contains(neighbor) else{continue}
                    let n=frame.normal*0.5,r=frame.right*0.5,u=frame.up*0.5
                    var path=Path();path.addLines([c+n-r-u,c+n+r-u,c+n+r+u,c+n-r+u].map(screen));path.closeSubpath()
                    context.fill(path,with:.color(frame.normal.y>0 ? Color(red:0.65,green:0.69,blue:0.94):Color(red:0.39,green:0.44,blue:0.79)))
                    context.stroke(path,with:.color(.primary),lineWidth:1.2)
                }
            }
            for (label,end) in [("+x",SIMD3<Double>(extent+0.2,0,0)),("+y",SIMD3<Double>(0,0,-extent-0.2)),("+z",SIMD3<Double>(0,extent+0.2,0))]{context.draw(Text(label).font(.caption.bold()),at:screen(end))}
        }
    }
}
private struct NFSpatialAssemblyRealityView:View {
    let cells:[NFSpatialAssemblyGeometry.Cell]
    let camera:String
    let allowsOrbit:Bool
    var body:some View {
        RealityView{content in
            content.camera = .virtual
            let root=Entity()
            if NFSpatialAssemblyGeometry.permits(cells){
                let extent=Float(max(cells.map(\.x).max() ?? 0,max(cells.map(\.y).max() ?? 0,cells.map(\.z).max() ?? 0))+1)
                for c in cells{
                    let model=ModelEntity(mesh:.generateBox(size:0.98),materials:[SimpleMaterial(color:.systemIndigo,isMetallic:false)])
                    model.position=[Float(c.x)+0.5-extent/2,Float(c.z)+0.5-extent/2,-Float(c.y)-0.5+extent/2]
                    root.addChild(model)
                }
                if camera == "Authored view"{root.orientation=simd_quatf(angle:Float(atan(1/sqrt(2.0))),axis:[1,0,0])*simd_quatf(angle:-.pi/4,axis:[0,1,0])}
                if camera == "Side"{root.orientation=simd_quatf(angle:-.pi/2,axis:[0,1,0])}
                if camera == "Top"{root.orientation=simd_quatf(angle:.pi/2,axis:[1,0,0])}
            }
            content.add(root);content.cameraTarget=root
        }placeholder:{ProgressView("Preparing 3D model")}
            .realityViewCameraControls(allowsOrbit ? .orbit:.none)
            .frame(minHeight:250,idealHeight:280)
    }
}
