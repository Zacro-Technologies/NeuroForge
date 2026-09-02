import Foundation

struct NFCubeNetCell: Codable, Equatable, Hashable, Sendable {
    let x: Int
    let y: Int
    let label: String

    init(x: Int, y: Int, label: String = "") {
        self.x = x
        self.y = y
        self.label = label
    }
}

struct NFCubeNetLayout: Codable, Equatable, Sendable {
    let cells: [NFCubeNetCell]

    var encodedDescription: String {
        let placements = cells
            .sorted(by: NFCubeNetEngine.cellOrder)
            .map { "\($0.label)@\($0.x),\($0.y)" }
            .joined(separator: ";")
        return "A valid cube net [\(placements)]"
    }

    init(cells: [NFCubeNetCell]) {
        self.cells = cells
    }

    init?(encodedDescription: String) {
        guard let open = encodedDescription.firstIndex(of: "["),
              let close = encodedDescription.lastIndex(of: "]"),
              open < close else { return nil }
        let entries = encodedDescription[encodedDescription.index(after: open)..<close]
            .split(separator: ";")
        let cells = entries.compactMap { entry -> NFCubeNetCell? in
            let labelAndCoordinate = entry.split(separator: "@", omittingEmptySubsequences: false)
            guard labelAndCoordinate.count == 2 else { return nil }
            let coordinate = labelAndCoordinate[1].split(separator: ",", omittingEmptySubsequences: false)
            guard coordinate.count == 2,
                  let x = Int(coordinate[0]),
                  let y = Int(coordinate[1]) else { return nil }
            return NFCubeNetCell(x: x, y: y, label: String(labelAndCoordinate[0]))
        }
        guard cells.count == entries.count else { return nil }
        self.cells = cells
    }
}

enum NFCubeNetEngine {
    private struct Vector: Equatable, Hashable {
        let x: Int
        let y: Int
        let z: Int

        static prefix func - (value: Vector) -> Vector {
            Vector(x: -value.x, y: -value.y, z: -value.z)
        }
    }

    private struct Orientation: Equatable {
        let normal: Vector
        let right: Vector
        let up: Vector
    }

    private struct Coordinate: Equatable, Hashable {
        let x: Int
        let y: Int
    }

    static let validCanonicalLayouts: [NFCubeNetLayout] = {
        var canonical: [String: [Coordinate]] = [:]
        for shape in enumerateConnectedHexominoes() where fold(shape) != nil {
            let normalized = canonicalFreeShape(shape)
            canonical[shapeKey(normalized)] = normalized
        }
        return canonical.keys.sorted().compactMap { key in
            canonical[key].map { coordinates in
                NFCubeNetLayout(cells: coordinates.enumerated().map { index, coordinate in
                    NFCubeNetCell(
                        x: coordinate.x,
                        y: coordinate.y,
                        label: String(UnicodeScalar(65 + index)!)
                    )
                })
            }
        }
    }()

    static func isValid(_ layout: NFCubeNetLayout) -> Bool {
        let coordinates = layout.cells.map { Coordinate(x: $0.x, y: $0.y) }
        return Set(coordinates).count == 6 && fold(coordinates) != nil
    }

    static func deterministicLayout(seed: UInt64) -> NFCubeNetLayout {
        precondition(!validCanonicalLayouts.isEmpty)
        let base = validCanonicalLayouts[Int(seed % UInt64(validCanonicalLayouts.count))]
        let offset = Int((seed >> 8) % 6)
        let labels = (0..<6).map { String(UnicodeScalar(65 + (($0 + offset) % 6))!) }
        return NFCubeNetLayout(cells: base.cells.enumerated().map { index, cell in
            NFCubeNetCell(x: cell.x, y: cell.y, label: labels[index])
        })
    }

    static func oppositeFace(to label: String, in layout: NFCubeNetLayout) -> String? {
        let coordinates = layout.cells.map { Coordinate(x: $0.x, y: $0.y) }
        guard let orientations = fold(coordinates),
              let sourceCell = layout.cells.first(where: { $0.label == label }),
              let sourceOrientation = orientations[Coordinate(x: sourceCell.x, y: sourceCell.y)] else {
            return nil
        }
        let oppositeNormal = -sourceOrientation.normal
        return layout.cells.first { cell in
            orientations[Coordinate(x: cell.x, y: cell.y)]?.normal == oppositeNormal
        }?.label
    }

    static func accessibilityDescription(for layout: NFCubeNetLayout) -> String {
        let origin = layout.cells.sorted(by: cellOrder).first?.label
            ?? NFAppLocalization.localized("the first face", locale: NFAppLocalization.preferredLocale, comment: "Fallback reference face in a cube-net accessibility description.")
        let placements = layout.cells.sorted(by: cellOrder).map { cell in
            NFAppLocalization.localized("\(cell.label) at column \(cell.x), row \(cell.y)", locale: NFAppLocalization.preferredLocale, comment: "One face placement in a cube-net accessibility description; placeholders are face label, column, and row.")
        }.joined(separator: "; ")
        return NFAppLocalization.localized("Cube net coordinates relative to \(origin): \(placements). Adjacency follows shared square edges.", locale: NFAppLocalization.preferredLocale, comment: "Accessibility description of a cube net; placeholders are the origin face and a list of face placements.")
    }

    fileprivate static func cellOrder(_ lhs: NFCubeNetCell, _ rhs: NFCubeNetCell) -> Bool {
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        return lhs.label < rhs.label
    }

    private static func fold(_ coordinates: [Coordinate]) -> [Coordinate: Orientation]? {
        let cells = Set(coordinates)
        guard cells.count == 6, let start = cells.sorted(by: coordinateOrder).first else { return nil }
        let initial = Orientation(
            normal: Vector(x: 0, y: 0, z: 1),
            right: Vector(x: 1, y: 0, z: 0),
            up: Vector(x: 0, y: 1, z: 0)
        )
        var orientations = [start: initial]
        var queue = [start]
        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            guard let orientation = orientations[current] else { return nil }
            let neighbors: [(Coordinate, Orientation)] = [
                (
                    Coordinate(x: current.x + 1, y: current.y),
                    Orientation(normal: orientation.right, right: -orientation.normal, up: orientation.up)
                ),
                (
                    Coordinate(x: current.x - 1, y: current.y),
                    Orientation(normal: -orientation.right, right: orientation.normal, up: orientation.up)
                ),
                (
                    Coordinate(x: current.x, y: current.y + 1),
                    Orientation(normal: orientation.up, right: orientation.right, up: -orientation.normal)
                ),
                (
                    Coordinate(x: current.x, y: current.y - 1),
                    Orientation(normal: -orientation.up, right: orientation.right, up: orientation.normal)
                )
            ]
            for (neighbor, foldedOrientation) in neighbors where cells.contains(neighbor) {
                if let existing = orientations[neighbor] {
                    guard existing == foldedOrientation else { return nil }
                } else {
                    orientations[neighbor] = foldedOrientation
                    queue.append(neighbor)
                }
            }
        }
        guard orientations.count == 6,
              Set(orientations.values.map(\.normal)).count == 6 else { return nil }
        return orientations
    }

    private static func enumerateConnectedHexominoes() -> [[Coordinate]] {
        var shapes = [[Coordinate(x: 0, y: 0)]]
        for _ in 1..<6 {
            var next: [String: [Coordinate]] = [:]
            for shape in shapes {
                let cells = Set(shape)
                for cell in shape {
                    let neighbors = [
                        Coordinate(x: cell.x + 1, y: cell.y),
                        Coordinate(x: cell.x - 1, y: cell.y),
                        Coordinate(x: cell.x, y: cell.y + 1),
                        Coordinate(x: cell.x, y: cell.y - 1)
                    ]
                    for neighbor in neighbors where !cells.contains(neighbor) {
                        let normalized = normalize(shape + [neighbor])
                        next[shapeKey(normalized)] = normalized
                    }
                }
            }
            shapes = next.keys.sorted().compactMap { next[$0] }
        }
        return shapes
    }

    private static func canonicalFreeShape(_ shape: [Coordinate]) -> [Coordinate] {
        let variants = (0..<8).map { transformIndex in
            normalize(shape.map { coordinate in
                switch transformIndex {
                case 0: Coordinate(x: coordinate.x, y: coordinate.y)
                case 1: Coordinate(x: -coordinate.y, y: coordinate.x)
                case 2: Coordinate(x: -coordinate.x, y: -coordinate.y)
                case 3: Coordinate(x: coordinate.y, y: -coordinate.x)
                case 4: Coordinate(x: -coordinate.x, y: coordinate.y)
                case 5: Coordinate(x: coordinate.x, y: -coordinate.y)
                case 6: Coordinate(x: coordinate.y, y: coordinate.x)
                default: Coordinate(x: -coordinate.y, y: -coordinate.x)
                }
            })
        }
        return variants.min { shapeKey($0) < shapeKey($1) } ?? normalize(shape)
    }

    private static func normalize(_ shape: [Coordinate]) -> [Coordinate] {
        let minimumX = shape.map(\.x).min() ?? 0
        let minimumY = shape.map(\.y).min() ?? 0
        return shape
            .map { Coordinate(x: $0.x - minimumX, y: $0.y - minimumY) }
            .sorted(by: coordinateOrder)
    }

    private static func coordinateOrder(_ lhs: Coordinate, _ rhs: Coordinate) -> Bool {
        lhs.y == rhs.y ? lhs.x < rhs.x : lhs.y < rhs.y
    }

    private static func shapeKey(_ shape: [Coordinate]) -> String {
        shape.sorted(by: coordinateOrder).map { "\($0.x),\($0.y)" }.joined(separator: ";")
    }
}
