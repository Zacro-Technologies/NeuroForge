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
/// The accompanying accessibility description is the authoritative nonvisual
/// equivalent; rendering is never part of deterministic scoring.
struct NFSpatialDiagramView: View {
    private enum Presentation: String, CaseIterable, Identifiable {
        case nativeThreeDimensional = "Native 3D"
        case staticTwoDimensional = "Static 2D"

        var id: String { rawValue }
    }

    let metadata: NFSpatialRepresentationMetadata
    let prefersReducedMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var presentation: Presentation = .nativeThreeDimensional

    init(metadata: NFSpatialRepresentationMetadata, prefersReducedMotion: Bool = false) {
        self.metadata = metadata
        self.prefersReducedMotion = prefersReducedMotion
    }

    private var reducesMotion: Bool {
        accessibilityReduceMotion || prefersReducedMotion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(metadata.dimension == .threeDimensional ? "3D model" : "2D diagram", systemImage: "move.3d")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(metadata.operations.map(\.title).joined(separator: " · "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            if metadata.dimension == .threeDimensional {
                Picker("Spatial rendering mode", selection: $presentation) {
                    ForEach(Presentation.allCases) { mode in
                        Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Switch between native three-dimensional geometry and an equivalent motion-free two-dimensional diagram.")

                if presentation == .nativeThreeDimensional {
                    NFSpatialRealityView(
                        metadata: metadata,
                        permitsOrbit: !reducesMotion
                    )
                    Text(reducesMotion
                         ? "Reduced Motion is active. The 3D camera is fixed; choose Static 2D for the equivalent diagram."
                         : "Drag the model to orbit. Nothing moves automatically; Static 2D is available above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    staticDiagram
                }
            } else {
                staticDiagram
            }

            Text(metadata.accessibilityDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Diagram description: \(metadata.accessibilityDescription)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var staticDiagram: some View {
        Canvas { context, size in
            drawBackground(in: &context, size: size)
            if !metadata.points.isEmpty {
                drawCoordinateStimulus(in: &context, size: size)
            } else if metadata.objectDescription.localizedCaseInsensitiveContains("cube net") {
                drawCubeNet(in: &context, size: size)
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

        let maximumCoordinate = max(
            2,
            metadata.points.flatMap { [abs($0.x), abs($0.y)] }.max() ?? 2
        ) + 1
        let scale = min(plot.width, plot.height) / CGFloat(maximumCoordinate * 2)
        for point in metadata.points {
            let location = CGPoint(
                x: origin.x + CGFloat(point.x) * scale,
                y: origin.y - CGFloat(point.y) * scale
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
        context.draw(Text(metadata.axisLabels.first ?? "x").font(.caption), at: CGPoint(x: plot.maxX - 6, y: origin.y + 14))
        if metadata.axisLabels.count > 1 {
            context.draw(Text(metadata.axisLabels[1]).font(.caption), at: CGPoint(x: origin.x + 14, y: plot.minY + 6))
        }
        if metadata.dimension == .threeDimensional {
            var zAxis = Path()
            zAxis.move(to: origin)
            zAxis.addLine(to: CGPoint(x: origin.x + plot.width * 0.22, y: origin.y + plot.height * 0.22))
            context.stroke(zAxis, with: .color(NFTheme.mint.opacity(0.8)), lineWidth: 2)
            context.draw(Text(metadata.axisLabels.dropFirst(2).first ?? "z").font(.caption), at: CGPoint(x: origin.x + plot.width * 0.24, y: origin.y + plot.height * 0.24))
        }
    }

    private func drawCubeNet(in context: inout GraphicsContext, size: CGSize) {
        let fallback = NFCubeNetLayout(cells: [
            NFCubeNetCell(x: 0, y: 0, label: "A"),
            NFCubeNetCell(x: 0, y: -1, label: "B"),
            NFCubeNetCell(x: 0, y: 1, label: "C"),
            NFCubeNetCell(x: -1, y: 0, label: "D"),
            NFCubeNetCell(x: 1, y: 0, label: "E"),
            NFCubeNetCell(x: 0, y: 2, label: "F")
        ])
        let layout = NFCubeNetLayout(encodedDescription: metadata.objectDescription) ?? fallback
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
        value.rounded() == value ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct NFSpatialRealityView: View {
    let metadata: NFSpatialRepresentationMetadata
    let permitsOrbit: Bool

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let scene = NFSpatialRealitySceneFactory.makeScene(for: metadata)
            content.add(scene)
            content.cameraTarget = scene
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

    static func makeScene(for metadata: NFSpatialRepresentationMetadata) -> Entity {
        let root = Entity()
        root.name = rootEntityName

        if !metadata.points.isEmpty {
            addCoordinateScene(to: root, metadata: metadata)
        } else if metadata.objectDescription.localizedCaseInsensitiveContains("cube net") {
            addFoldedCube(to: root, metadata: metadata)
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

    private static func addFoldedCube(
        to root: Entity,
        metadata: NFSpatialRepresentationMetadata
    ) {
        root.addChild(model(
            name: stimulusEntityName,
            mesh: .generateBox(size: 1.18, cornerRadius: 0.045),
            color: .systemIndigo,
            position: .zero
        ))
        let markerCount = max(2, Int((metadata.difficultyParameters.objectComplexity * 6).rounded()))
        let markerPositions: [SIMD3<Float>] = [
            [0.6, 0.34, 0.25], [0.22, 0.6, -0.28], [-0.6, 0.12, 0.3],
            [-0.24, -0.6, -0.32], [0.3, -0.2, 0.6], [-0.31, 0.26, -0.6]
        ]
        for index in 0..<min(markerCount, markerPositions.count) {
            root.addChild(model(
                name: "face.marker.\(index)",
                mesh: .generateSphere(radius: 0.075),
                color: index.isMultiple(of: 2) ? .systemOrange : .systemTeal,
                position: markerPositions[index]
            ))
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
