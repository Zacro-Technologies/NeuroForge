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

    static func accessibilityDescription(for layout: NFCubeNetLayout, locale: Locale = NFAppLocalization.preferredLocale) -> String {
        let origin = layout.cells.sorted(by: cellOrder).first?.label
            ?? NFAppLocalization.localized("the first face", locale: locale, comment: "Fallback reference face in a cube-net accessibility description.")
        let placements = layout.cells.sorted(by: cellOrder).map { cell in
            NFAppLocalization.localized("\(cell.label) at column \(cell.x), row \(cell.y)", locale: locale, comment: "One face placement in a cube-net accessibility description; placeholders are face label, column, and row.")
        }.joined(separator: "; ")
        return NFAppLocalization.localized("Cube net coordinates relative to \(origin): \(placements). Adjacency follows shared square edges.", locale: locale, comment: "Accessibility description of a cube net; placeholders are the origin face and a list of face placements.")
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


/// Bounded, labeled geometry for one of the actual retained net layouts. These
/// face frames are used only for an explicitly permitted endpoint demonstration.
struct NFCubeNetDisplayFace: Equatable, Sendable {
    let label: String
    let column: Int
    let row: Int
    let normal: SIMD3<Int32>
    let right: SIMD3<Int32>
    let up: SIMD3<Int32>
    func directionTitle(locale: Locale) -> String {
        let key: String
        switch normal {
        case SIMD3(1, 0, 0): key = "positive x"
        case SIMD3(-1, 0, 0): key = "negative x"
        case SIMD3(0, 1, 0): key = "positive y"
        case SIMD3(0, -1, 0): key = "negative y"
        case SIMD3(0, 0, 1): key = "positive z"
        default: key = "negative z"
        }
        return NFAppLocalization.localizedCatalogValue(key, locale: locale)
    }
}

extension NFCubeNetEngine {
    static func displayFaces(encodedDescription: String) -> [NFCubeNetDisplayFace]? {
        guard encodedDescription.utf8.count <= 2_048,
              encodedDescription.hasPrefix("A valid cube net ["), encodedDescription.hasSuffix("]"),
              let layout = NFCubeNetLayout(encodedDescription: encodedDescription), layout.cells.count == 6,
              layout.cells.allSatisfy({ (-64...64).contains($0.x) && (-64...64).contains($0.y)
                && !$0.label.isEmpty && $0.label.utf8.count <= 32 }),
              Set(layout.cells.map(\.label)).count == 6,
              let folded = fold(layout.cells.map { Coordinate(x: $0.x, y: $0.y) }) else { return nil }
        return layout.cells.sorted(by: cellOrder).compactMap { cell in
            guard let orientation = folded[Coordinate(x: cell.x, y: cell.y)] else { return nil }
            func vector(_ value: Vector) -> SIMD3<Int32> { SIMD3(Int32(value.x), Int32(value.y), Int32(value.z)) }
            return .init(label: cell.label, column: cell.x, row: cell.y,
                normal: vector(orientation.normal), right: vector(orientation.right), up: vector(orientation.up))
        }
    }
}


/// Exact, bounded geometry for the new ordinary spatial recipe. No prose is
/// parsed to recover an object, query, transform, or accepted alternative.
enum NFSpatialStructureGeometry {
    struct Cell: Codable, Equatable, Hashable, Sendable, Comparable {
        let x: Int
        let y: Int
        let z: Int
        static func < (a: Self, b: Self) -> Bool { a.z == b.z ? (a.y == b.y ? a.x < b.x : a.y < b.y) : a.z < b.z }
        var token: String { "\(x),\(y),\(z)" }
    }
    struct Square: Codable, Equatable, Hashable, Sendable, Comparable {
        let x: Int
        let y: Int
        static func < (a: Self, b: Self) -> Bool { a.y == b.y ? a.x < b.x : a.y < b.y }
        var token: String { "\(x),\(y)" }
    }
    enum Axis: String, Codable, CaseIterable, Equatable, Sendable { case x, y, z }
    enum Direction: String, Codable, CaseIterable, Equatable, Sendable {
        case positiveX, negativeX, positiveY, negativeY, positiveZ, negativeZ
        var vector: [Int] {
            switch self { case .positiveX: [1,0,0]; case .negativeX: [-1,0,0]; case .positiveY: [0,1,0]; case .negativeY: [0,-1,0]; case .positiveZ: [0,0,1]; case .negativeZ: [0,0,-1] }
        }
        var symbol: String { switch self { case .positiveX: "+x"; case .negativeX: "−x"; case .positiveY: "+y"; case .negativeY: "−y"; case .positiveZ: "+z"; case .negativeZ: "−z" } }
    }
    struct Rotation: Codable, Equatable, Sendable {
        let axis: Axis
        let quarterTurns: Int
        var isValid: Bool { (1...3).contains(quarterTurns) }
        var token: String { axis.rawValue + String(quarterTurns) }
    }
    struct FaceRotation: Codable, Equatable, Sendable {
        let rotations: [Rotation]
        let query: Direction
        /// Labels and initial normals are fixed; relabeling does not create a
        /// new item. This key also collapses equivalent composed operations.
        var identity: String { "faces." + NFSpatialStructureGeometry.transform([1,2,3], by: rotations).map(String.init).joined(separator: ",") + "." + query.rawValue }
        var correctFace: String? {
            guard !rotations.isEmpty, rotations.count <= 2, rotations.allSatisfy(\.isValid) else { return nil }
            return zip(Self.labels, Direction.allCases).first {
                NFSpatialStructureGeometry.transform($0.1.vector, by: rotations) == query.vector
            }?.0
        }
        static let labels = ["A", "B", "C", "D", "E", "F"]
        func finalDirection(face: String, steps: Int? = nil) -> Direction? {
            guard let index = Self.labels.firstIndex(of: face) else { return nil }
            let value = NFSpatialStructureGeometry.transform(Direction.allCases[index].vector,
                by: Array(rotations.prefix(steps ?? rotations.count)))
            return Direction.allCases.first { $0.vector == value }
        }
    }
    struct TopView: Codable, Equatable, Sendable {
        let cells: [Cell]
        let choices: [[Square]]
        var footprint: [Square] { Array(Set(cells.map { Square(x: $0.x, y: $0.y) })).sorted() }
        var identity: String { "top." + NFSpatialStructureGeometry.canonical(footprint).map(\.token).joined(separator: ";") }
        var correctIndices: [Int] { choices.indices.filter { choices[$0].sorted() == footprint } }
    }
    struct ViewConstraints: Codable, Equatable, Sendable {
        /// Front is x versus z, looking from negative y. Side is y versus z,
        /// looking from positive x; screen horizontal values follow the labels.
        let frontHeights: [Int]
        let sideHeights: [Int]
        let candidates: [[Cell]]
        var identity: String {
            let versions = [(frontHeights,sideHeights),(sideHeights,frontHeights)].flatMap { a,b in
                [a,Array(a.reversed())].flatMap { x in [b,Array(b.reversed())].map { x + $0 } }
            }
            return "views." + (versions.map { $0.map(String.init).joined(separator: ",") }.min() ?? "")
        }
        var correctIndices: [Int] {
            candidates.indices.filter { index in
                let cells = candidates[index]
                return NFSpatialStructureGeometry.heights(cells, axis: .x) == frontHeights
                    && NFSpatialStructureGeometry.heights(cells, axis: .y) == sideHeights
            }
        }
    }
    enum Structure: Codable, Equatable, Sendable {
        case faces(FaceRotation), top(TopView), views(ViewConstraints)
        var identity: String { switch self { case let .faces(v): v.identity; case let .top(v): v.identity; case let .views(v): v.identity } }
        var variant: Int { if case .faces = self { return 1 }; return 3 }
        var isBounded: Bool {
            switch self {
            case let .faces(v): return !v.rotations.isEmpty && v.rotations.count <= 2 && v.rotations.allSatisfy(\.isValid)
            case let .top(v): return NFSpatialStructureGeometry.permits(v.cells) && v.choices.count == 4
                && v.choices.allSatisfy { (4...5).contains($0.count) && Set($0).count == $0.count
                    && $0.allSatisfy { (0...4).contains($0.x) && (0...4).contains($0.y) } }
            case let .views(v): return v.frontHeights.count == 2 && v.sideHeights.count == 2
                && (v.frontHeights+v.sideHeights).allSatisfy { (1...3).contains($0) }
                && v.candidates.count == 4 && v.candidates.allSatisfy { NFSpatialStructureGeometry.permits($0) }
            }
        }
        var dependentSteps: Int { switch self { case let .faces(v): v.rotations.count; case .top: 1; case .views: 2 } }
    }
    static func transform(_ source: [Int], by rotations: [Rotation]) -> [Int] {
        guard source.count == 3, source.allSatisfy({ (-16...16).contains($0) }), rotations.count <= 2, rotations.allSatisfy(\.isValid) else { return [] }
        var v = source
        for operation in rotations {
            for _ in 0..<operation.quarterTurns {
                switch operation.axis {
                case .x: v = [v[0], -v[2], v[1]]
                case .y: v = [v[2], v[1], -v[0]]
                case .z: v = [-v[1], v[0], v[2]]
                }
            }
        }
        return v
    }
    static func permits(_ cells: [Cell]) -> Bool {
        guard !cells.isEmpty, cells.count <= 18, Set(cells).count == cells.count,
              cells.allSatisfy({ (0...4).contains($0.x) && (0...4).contains($0.y) && (0...2).contains($0.z) }) else { return false }
        let occupied = Set(cells)
        guard cells.allSatisfy({ $0.z == 0 || occupied.contains(.init(x: $0.x, y: $0.y, z: $0.z - 1)) }) else { return false }
        var reached: Set<Cell> = [cells[0]], frontier = [cells[0]]
        while let current = frontier.popLast() {
            for v in [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)] {
                let next = Cell(x: current.x+v.0, y: current.y+v.1, z: current.z+v.2)
                if occupied.contains(next), reached.insert(next).inserted { frontier.append(next) }
            }
        }
        return reached.count == cells.count
    }
    static func heights(_ cells: [Cell], axis: Axis) -> [Int] {
        guard axis != .z, permits(cells) else { return [] }
        let largest = cells.map { axis == .x ? $0.x : $0.y }.max() ?? 0
        return (0...largest).map { coordinate in cells.filter { (axis == .x ? $0.x : $0.y) == coordinate }.map { $0.z + 1 }.max() ?? 0 }
    }
    static func cells(heights: [Int]) -> [Cell] {
        guard heights.count == 4, heights.allSatisfy({ (1...3).contains($0) }) else { return [] }
        return heights.enumerated().flatMap { index,height in (0..<height).map { Cell(x: index % 2, y: index / 2, z: $0) } }.sorted()
    }
    static func normalized(_ values: [Square]) -> [Square] {
        let lowX = values.map(\.x).min() ?? 0, lowY = values.map(\.y).min() ?? 0
        return values.map { Square(x: $0.x-lowX, y: $0.y-lowY) }.sorted()
    }
    static func canonical(_ values: [Square]) -> [Square] {
        guard !values.isEmpty, values.count <= 5, values.allSatisfy({ (-5...5).contains($0.x) && (-5...5).contains($0.y) }) else { return [] }
        let versions = (0..<8).map { index in normalized(values.map { v in
            switch index { case 0: Square(x:v.x,y:v.y); case 1: Square(x:-v.y,y:v.x); case 2: Square(x:-v.x,y:-v.y); case 3: Square(x:v.y,y:-v.x); case 4: Square(x:-v.x,y:v.y); case 5: Square(x:v.x,y:-v.y); case 6: Square(x:v.y,y:v.x); default: Square(x:-v.y,y:-v.x) }
        }) }
        return versions.min { $0.map(\.token).joined(separator:";") < $1.map(\.token).joined(separator:";") } ?? []
    }
    static let footprints: [[Square]] = {
        var shapes = [[Square(x:0,y:0)]], result: [[Square]] = []
        for count in 2...5 {
            var distinct: [String:[Square]] = [:]
            for shape in shapes {
                for square in shape {
                    for d in [(1,0),(-1,0),(0,1),(0,-1)] {
                        let next = Square(x:square.x+d.0,y:square.y+d.1)
                        guard !shape.contains(next) else { continue }
                        let key = canonical(shape+[next]); distinct[key.map(\.token).joined(separator:";")] = key
                    }
                }
            }
            shapes = distinct.keys.sorted().compactMap { distinct[$0] }
            if count >= 4 { result += shapes }
        }
        return result
    }()
    static let structures: [Structure] = {
        var result: [Structure] = [], seen: Set<String> = []
        let rotations = Axis.allCases.flatMap { axis in (1...3).map { Rotation(axis:axis,quarterTurns:$0) } }
        let paths = rotations.map { [$0] } + rotations.flatMap { first in rotations.filter { $0.axis != first.axis }.map { [first,$0] } }
        for path in paths {
            for query in Direction.allCases {
                let value = FaceRotation(rotations:path,query:query)
                if value.correctFace != nil, seen.insert(value.identity).inserted { result.append(.faces(value)) }
            }
        }
        for (ordinal,footprint) in footprints.enumerated() {
            let others = footprints.filter { $0.count == footprint.count && $0 != footprint }.prefix(3)
            let occupied = footprint.enumerated().flatMap { index,square in
                (0..<(index % 2 + 1)).map { Cell(x:square.x,y:square.y,z:$0) }
            }.sorted()
            let alternatives = [footprint]+Array(others)
            let shift = ordinal % 4
            let value = TopView(cells:occupied,choices:Array(alternatives.dropFirst(shift))+Array(alternatives.prefix(shift)))
            if permits(occupied), value.choices.count == 4, value.correctIndices.count == 1 { result.append(.top(value)) }
        }
        var all: [[Cell]] = []
        for a in 1...3 { for b in 1...3 { for c in 1...3 { for d in 1...3 { all.append(cells(heights:[a,b,c,d])) } } } }
        var pairs: Set<String> = [], viewClasses: Set<String> = []
        for source in all {
            let front = heights(source,axis:.x), side = heights(source,axis:.y)
            let key = (front+side).map(String.init).joined(separator:",")
            guard pairs.insert(key).inserted else { continue }
            let valid = all.filter { heights($0,axis:.x) == front && heights($0,axis:.y) == side }
            guard valid.count >= 2 else { continue }
            var wrong: [[Cell]] = []
            // Each rival satisfies at least one supplied view when possible.
            for axis in [Axis.x,.y] {
                if let candidate = all.first(where: { (axis == .x ? heights($0,axis:.x) == front : heights($0,axis:.y) == side) && !valid.contains($0) && !wrong.contains($0) }) { wrong.append(candidate) }
            }
            for candidate in all where wrong.count < 2 && !valid.contains(candidate) && !wrong.contains(candidate) { wrong.append(candidate) }
            guard wrong.count == 2 else { continue }
            let validPositions = [[0,1],[0,2,3],[0,3],[1,2,3]][viewClasses.count % 4]
            // Keep the authored multiplicity exact; never index a missing alternative.
            guard valid.count >= validPositions.count else { continue }
            var validIndex = 0, wrongIndex = 0
            let proposed = (0..<4).map { position -> [Cell] in
                if validPositions.contains(position) { defer { validIndex += 1 }; return valid[validIndex] }
                defer { wrongIndex += 1 }; return wrong[wrongIndex]
            }
            let value = ViewConstraints(frontHeights:front,sideHeights:side,candidates:proposed)
            if viewClasses.insert(value.identity).inserted { result.append(.views(value)) }
        }
        return result
    }()
}


/// Bounded integer affine isometries for ordinary coordinate practice. All
/// rendered givens, response coordinates and replay states use this value model.
enum NFCoordinateTransformGeometry {
    struct Point: Codable, Equatable, Hashable, Sendable {
        let x: Int
        let y: Int
        var isBounded: Bool { (-24...24).contains(x) && (-24...24).contains(y) }
        var token: String { "\(x),\(y)" }
    }
    enum Mirror: String, Codable, CaseIterable, Equatable, Hashable, Sendable { case vertical, horizontal, risingDiagonal, fallingDiagonal }
    enum Operation: Codable, Equatable, Sendable {
        case rotate(center: Point, quarterTurns: Int)
        case translate(vector: Point)
        case reflect(line: Mirror, offset: Int)
        var isBounded: Bool {
            switch self {
            case let .rotate(c,q): return c.isBounded && (-3...3).contains(q) && q != 0
            case let .translate(v): return v.isBounded && v != .init(x:0,y:0)
            case let .reflect(line,c): return (-4...4).contains(c) && (line == .vertical || line == .horizontal || c == 0)
            }
        }
        var anchor: Point {
            switch self {
            case let .rotate(c,_): c
            case .translate: .init(x:0,y:0)
            case let .reflect(line,c): line == .vertical ? .init(x:c,y:0) : line == .horizontal ? .init(x:0,y:c) : .init(x:0,y:0)
            }
        }
        var affine: Affine? {
            guard isBounded else { return nil }
            switch self {
            case let .rotate(center,q):
                let m: [Int]
                switch (q % 4 + 4) % 4 { case 1: m=[0,-1,1,0]; case 2: m=[-1,0,0,-1]; case 3: m=[0,1,-1,0]; default: return nil }
                return .init(a:m[0],b:m[1],c:m[2],d:m[3],tx:center.x-m[0]*center.x-m[1]*center.y,ty:center.y-m[2]*center.x-m[3]*center.y)
            case let .translate(v): return .init(a:1,b:0,c:0,d:1,tx:v.x,ty:v.y)
            case let .reflect(line,k):
                switch line {
                case .vertical: return .init(a:-1,b:0,c:0,d:1,tx:2*k,ty:0)
                case .horizontal: return .init(a:1,b:0,c:0,d:-1,tx:0,ty:2*k)
                case .risingDiagonal: return .init(a:0,b:1,c:1,d:0,tx:0,ty:0)
                case .fallingDiagonal: return .init(a:0,b:-1,c:-1,d:0,tx:0,ty:0)
                }
            }
        }
    }
    struct Affine: Equatable, Sendable {
        let a: Int, b: Int, c: Int, d: Int, tx: Int, ty: Int
        static let identity = Self(a:1,b:0,c:0,d:1,tx:0,ty:0)
        var determinant: Int { a*d-b*c }
        func applying(_ p: Point) -> Point { .init(x:a*p.x+b*p.y+tx,y:c*p.x+d*p.y+ty) }
        /// self after the earlier transform; order is explicit.
        func after(_ earlier: Self) -> Self {
            .init(a:a*earlier.a+b*earlier.c,b:a*earlier.b+b*earlier.d,
                c:c*earlier.a+d*earlier.c,d:c*earlier.b+d*earlier.d,
                tx:a*earlier.tx+b*earlier.ty+tx,ty:c*earlier.tx+d*earlier.ty+ty)
        }
    }
    enum TaskKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
        case rotateOrigin, rotateOffset, translateThenRotate, rotateThenTranslate
        case reflectAxis, reflectOffset, reflectDiagonal, reflectTwice, rotateThenReflect, reflectThenRotate
        var variant: Int { switch self { case .rotateOrigin,.rotateOffset,.translateThenRotate,.rotateThenTranslate: 0; default: 5 } }
    }
    struct Task: Codable, Equatable, Sendable {
        let kind: TaskKind
        let point: Point
        let operations: [Operation]
        var isBounded: Bool {
            point.isBounded && (1...2).contains(operations.count) && operations.allSatisfy(\.isBounded)
                && steps.count == operations.count + 1 && steps.allSatisfy(\.isBounded)
        }
        var affine: Affine? {
            guard (1...2).contains(operations.count),operations.allSatisfy(\.isBounded) else { return nil }
            return operations.reduce(Affine.identity) { $1.affine!.after($0) }
        }
        var steps: [Point] {
            guard point.isBounded,(1...2).contains(operations.count),operations.allSatisfy(\.isBounded) else { return [] }
            var result=[point]
            for operation in operations { result.append(operation.affine!.applying(result.last!)) }
            return result
        }
        var answer: Point? { isBounded ? steps.last : nil }
        /// Exact repeated numbers are not independent geometry. Remove the
        /// common anchor and canonicalize the complete task under D4; scale
        /// equivalent source/translation vectors share an identity as well.
        var semanticIdentity: String {
            guard isBounded,let first=operations.first else { return "unavailable" }
            if operations.count == 1,answer == point { return "coordinate."+kind.rawValue+".fixed-point" }
            let origin=first.anchor
            let p=Point(x:point.x-origin.x,y:point.y-origin.y)
            let moves=operations.compactMap(\.affine).map { f in
                Affine(a:f.a,b:f.b,c:f.c,d:f.d,
                    tx:f.a*origin.x+f.b*origin.y+f.tx-origin.x,
                    ty:f.c*origin.x+f.d*origin.y+f.ty-origin.y)
            }
            let symmetries=[Affine(a:1,b:0,c:0,d:1,tx:0,ty:0),.init(a:0,b:-1,c:1,d:0,tx:0,ty:0),
                .init(a:-1,b:0,c:0,d:-1,tx:0,ty:0),.init(a:0,b:1,c:-1,d:0,tx:0,ty:0),
                .init(a:-1,b:0,c:0,d:1,tx:0,ty:0),.init(a:1,b:0,c:0,d:-1,tx:0,ty:0),
                .init(a:0,b:1,c:1,d:0,tx:0,ty:0),.init(a:0,b:-1,c:-1,d:0,tx:0,ty:0)]
            let versions=symmetries.map { s -> String in
                let inverse=Affine(a:s.a,b:s.c,c:s.b,d:s.d,tx:0,ty:0)
                let q=s.applying(p), changed=moves.map { s.after($0).after(inverse) }
                let coordinates=[q.x,q.y]+changed.flatMap { [$0.tx,$0.ty] }
                let divisor=max(1,coordinates.reduce(0) { NFCoordinateTransformGeometry.gcd($0,abs($1)) })
                return ([q.x/divisor,q.y/divisor]+changed.flatMap { [$0.a,$0.b,$0.c,$0.d,$0.tx/divisor,$0.ty/divisor] }).map(String.init).joined(separator:",")
            }
            return "coordinate."+kind.rawValue+"."+(versions.min() ?? "unavailable")
        }
    }
    private static func gcd(_ a: Int,_ b: Int) -> Int { var x=a,y=b;while y != 0 { let r=x%y;x=y;y=r };return x }
    /// Coverage cases include all quadrants, both axes, the origin, symmetry and
    /// center/line fixed points. They do not inflate structural capacity.
    static let sourcePoints: [Point] = [(-3,-2),(-3,2),(3,-2),(3,2),(0,-3),(0,3),(-3,0),(3,0),(0,0),(2,2),(-2,-2),(2,-2),(-2,2),(1,-1)].map { .init(x:$0.0,y:$0.1) }
    static let tasks: [Task] = {
        let zero=Point(x:0,y:0),offset=Point(x:1,y:-1),translation=Point(x:2,y:1)
        var recipes: [(TaskKind,[Operation])] = []
        for turns in [-3,-2,-1,1,2,3] {
            recipes.append((.rotateOrigin,[.rotate(center:zero,quarterTurns:turns)]))
            recipes.append((.rotateOffset,[.rotate(center:offset,quarterTurns:turns)]))
        }
        recipes += [(.translateThenRotate,[.translate(vector:translation),.rotate(center:offset,quarterTurns:1)]),
            (.rotateThenTranslate,[.rotate(center:offset,quarterTurns:1),.translate(vector:translation)]),
            (.reflectAxis,[.reflect(line:.vertical,offset:0)]),(.reflectAxis,[.reflect(line:.horizontal,offset:0)]),
            (.reflectOffset,[.reflect(line:.vertical,offset:1)]),(.reflectOffset,[.reflect(line:.horizontal,offset:-1)]),
            (.reflectDiagonal,[.reflect(line:.risingDiagonal,offset:0)]),(.reflectDiagonal,[.reflect(line:.fallingDiagonal,offset:0)]),
            (.reflectTwice,[.reflect(line:.vertical,offset:1),.reflect(line:.horizontal,offset:-1)]),
            (.reflectTwice,[.reflect(line:.vertical,offset:0),.reflect(line:.risingDiagonal,offset:0)]),
            (.rotateThenReflect,[.rotate(center:offset,quarterTurns:1),.reflect(line:.risingDiagonal,offset:0)]),
            (.reflectThenRotate,[.reflect(line:.risingDiagonal,offset:0),.rotate(center:offset,quarterTurns:1)])]
        return recipes.flatMap { kind,operations in sourcePoints.map { Task(kind:kind,point:$0,operations:operations) } }.filter(\.isBounded)
    }()
}


/// Bounded solid/plane geometry. Cube edge intersections are exact dyadic
/// coordinates on the admitted parameter domain; sphere radii retain a rational
/// authority. Render sampling is never used to classify or score a section.
enum NFSolidSectionGeometry {
    struct Point: Codable, Equatable, Hashable, Sendable {
        let x: Double, y: Double, z: Double
        var vector: [Double] { [x,y,z] }
        static func + (a:Self,b:Self)->Self { .init(x:a.x+b.x,y:a.y+b.y,z:a.z+b.z) }
        static func - (a:Self,b:Self)->Self { .init(x:a.x-b.x,y:a.y-b.y,z:a.z-b.z) }
        static func * (a:Self,b:Double)->Self { .init(x:a.x*b,y:a.y*b,z:a.z*b) }
        func dot(_ p:Self)->Double { x*p.x+y*p.y+z*p.z }
        func cross(_ p:Self)->Self { .init(x:y*p.z-z*p.y,y:z*p.x-x*p.z,z:x*p.y-y*p.x) }
        var squaredLength:Double { dot(self) }
        var unit:Self { self * (1 / sqrt(squaredLength)) }
        static let zero=Self(x:0,y:0,z:0)
    }
    struct Plane: Codable, Equatable, Hashable, Sendable {
        let a:Int,b:Int,c:Int,twiceOffset:Int
        var normal:Point { .init(x:Double(a),y:Double(b),z:Double(c)) }
        var offset:Double { Double(twiceOffset)/2 }
        var normSquared:Int { a*a+b*b+c*c }
        var isBounded:Bool { (-2...2).contains(a) && (-2...2).contains(b) && (-2...2).contains(c)
            && (-24...24).contains(twiceOffset) && (a != 0 || b != 0 || c != 0) }
        func contains(_ p:Point)->Bool { normal.dot(p) == offset }
        var center:Point { normal * (offset/Double(normSquared)) }
        var basis:(Point,Point) {
            let n=normal.unit,axis=abs(n.z)<0.9 ? Point(x:0,y:0,z:1):Point(x:0,y:1,z:0)
            let u=n.cross(axis).unit;return(u,n.cross(u))
        }
    }
    enum Solid:String,Codable,CaseIterable,Hashable,Sendable { case cube,sphere,cylinder }
    enum Shape:String,Codable,CaseIterable,Hashable,Sendable {
        case empty,point,segment,triangle,square,rectangle,rhombus,quadrilateral,pentagon,hexagon,circle,ellipse,clippedEllipse
        var dimension:Int { switch self { case .empty: -1;case .point:0;case .segment:1;default:2 } }
    }
    enum Query:Codable,Equatable,Hashable,Sendable {
        case classify
        case sphereRadiusSquared
        case verify(shape:Shape,through:Point)
    }
    struct Task:Codable,Equatable,Hashable,Sendable {
        let solid:Solid,plane:Plane,query:Query
        var isBounded:Bool {
            guard plane.isBounded else { return false }
            if case let .verify(_,point)=query {
                guard point.vector.allSatisfy({ $0.isFinite && (-2...2).contains($0) && $0.rounded() == $0 }) else { return false }
            }
            return true
        }
        var radiusSquared:NFExactNumber? {
            guard solid == .sphere,plane.isBounded else { return nil }
            let denominator=4*plane.normSquared,numerator=9*denominator-plane.twiceOffset*plane.twiceOffset
            return try? .init(numerator:Int64(numerator),denominator:Int64(denominator))
        }
        var cubeVertices:[Point] {
            guard solid == .cube,plane.isBounded else { return [] }
            let corners=Self.corners
            var points:Set<Point>=[]
            for (i,p) in corners.enumerated() {
                for q in corners.dropFirst(i+1) where zip(p.vector,q.vector).filter({$0 != $1}).count == 1 {
                    let a=plane.normal.dot(p)-plane.offset,b=plane.normal.dot(q)-plane.offset
                    if a == 0 { points.insert(p) };if b == 0 { points.insert(q) }
                    if a*b < 0 { points.insert(p+(q-p)*(a/(a-b))) }
                }
            }
            let values=Array(points),center=values.reduce(.zero,+)*(1/Double(max(1,values.count))),basis=plane.basis
            return values.sorted { p,q in
                let x=p-center,y=q-center
                return atan2(x.dot(basis.1),x.dot(basis.0)) < atan2(y.dot(basis.1),y.dot(basis.0))
            }
        }
        var shape:Shape? {
            guard isBounded else { return nil }
            switch solid {
            case .cube:
                let points=cubeVertices
                switch points.count {
                case 0:return .empty;case 1:return .point;case 2:return .segment;case 3:return .triangle
                case 5:return .pentagon;case 6:return .hexagon
                case 4:
                    let edges=points.indices.map { points[($0+1)%4]-points[$0] }
                    let equal=edges.allSatisfy { $0.squaredLength == edges[0].squaredLength }
                    let right=edges.indices.allSatisfy { edges[$0].dot(edges[($0+1)%4]) == 0 }
                    if right { return equal ? .square:.rectangle }
                    return equal ? .rhombus:.quadrilateral
                default:return nil
                }
            case .sphere:
                let difference=36*plane.normSquared-plane.twiceOffset*plane.twiceOffset
                return difference < 0 ? .empty : difference == 0 ? .point:.circle
            case .cylinder:
                // Only these exact axial/oblique normals are in the finite
                // recipe. Unknown orientations are not guessed from a drawing.
                guard plane.b == 0,[0,1].contains(plane.a),[0,1].contains(plane.c) else { return nil }
                let d=abs(plane.offset)
                if plane.a == 0 { return d <= 3 ? .circle:.empty }
                if plane.c == 0 { return d > 2 ? .empty:d == 2 ? .segment:.rectangle }
                return d > 5 ? .empty:d == 5 ? .point:d <= 1 ? .ellipse:.clippedEllipse
            }
        }
        var verifiesClaim:Bool? {
            guard case let .verify(proposed,point)=query,let shape else { return nil }
            return shape.dimension == 2 && shape == proposed && plane.contains(point)
        }
        var boundary:[Point] {
            guard let shape,shape != .empty else { return [] }
            if solid == .cube { return cubeVertices }
            if solid == .sphere {
                if shape == .point { return [plane.center] }
                let radius=sqrt(max(0,radiusSquared?.doubleValue ?? 0)),basis=plane.basis
                return (0..<96).map { i in let t=Double(i)*2*Double.pi/96
                    return plane.center+basis.0*(radius*cos(t))+basis.1*(radius*sin(t)) }
            }
            if plane.a == 0 {
                return (0..<96).map { i in let t=Double(i)*2*Double.pi/96
                    return .init(x:2*cos(t),y:2*sin(t),z:plane.offset) }
            }
            if plane.c == 0 {
                let y=sqrt(max(0,4-plane.offset*plane.offset))
                if shape == .segment { return [.init(x:plane.offset,y:0,z:-3),.init(x:plane.offset,y:0,z:3)] }
                return [.init(x:plane.offset,y:-y,z:-3),.init(x:plane.offset,y:y,z:-3),.init(x:plane.offset,y:y,z:3),.init(x:plane.offset,y:-y,z:3)]
            }
            if shape == .point { return [.init(x:plane.offset > 0 ? 2:-2,y:0,z:plane.offset > 0 ? 3:-3)] }
            let lower=max(-2,plane.offset-3),upper=min(2,plane.offset+3)
            // Two monotone circular arcs meet at exact cap-cut endpoints. No
            // low-resolution sample can omit the straight closing boundary.
            let angles=(acos(upper/2),acos(lower/2))
            let upperArc=(0...48).map { i -> Point in
                let t=angles.0+(angles.1-angles.0)*Double(i)/48,x=2*cos(t)
                return .init(x:x,y:2*sin(t),z:plane.offset-x) }
            let lowerArc=upperArc.reversed().map { Point(x:$0.x,y:-$0.y,z:$0.z) }
            return upperArc+lowerArc
        }
        static let corners:[Point]=[-2.0,2.0].flatMap { x in [-2.0,2.0].flatMap { y in [-2.0,2.0].map { z in .init(x:x,y:y,z:z) } } }
        var identity:String {
            guard isBounded else { return "invalid" }
            return NFSolidSectionGeometry.identities[self] ?? computedIdentity
        }
        fileprivate var computedIdentity:String {
            guard isBounded else { return "invalid" }
            // Cube signed axis permutations; translations/signs of a display
            // alone cannot manufacture another independent section query.
            let normal=[plane.a,plane.b,plane.c]
            let point:Point? = { if case let .verify(_,p)=query { return p };return nil }()
            var codes:[String]=[]
            for permutation in [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]] {
                if solid == .cylinder && permutation[2] != 2 { continue }
                for sx in [-1,1] { for sy in [-1,1] { for sz in [-1,1] {
                    let signs=[sx,sy,sz]
                    let n=permutation.indices.map { normal[permutation[$0]]*signs[$0] }
                    let q=point.map { p in permutation.indices.map { Int(p.vector[permutation[$0]])*signs[$0] } } ?? []
                    for equationSign in [-1,1] {
                        let parts=n.map { $0*equationSign }+[plane.twiceOffset*equationSign]+q
                        codes.append(parts.map(String.init).joined(separator:","))
                    }
                } } }
            }
            let role:String
            switch query { case .classify:role="shape";case .sphereRadiusSquared:role="radius-squared";case let .verify(s,_):role="constraints-"+s.rawValue }
            if solid == .sphere,point == nil {
                if case .classify=query {
                    let position=plane.twiceOffset == 0 ? "central":"offset"
                    return "sphere.shape."+(shape?.rawValue ?? "invalid")+"."+position
                }
                return "sphere."+role+"."+(radiusSquared?.canonicalString ?? "invalid")
            }
            if case .classify=query,let shape {
                let orientation=[abs(plane.a),abs(plane.b),abs(plane.c)].sorted().map(String.init).joined(separator:",")
                if shape.dimension < 2 { return solid.rawValue+".shape."+shape.rawValue+"."+orientation }
                if solid == .cylinder {
                    let position=plane.twiceOffset == 0 ? "central":(plane.a == 0 && abs(plane.twiceOffset) == 6 ? "end-cap":"offset")
                    return "cylinder.shape."+shape.rawValue+"."+String(plane.c)+"."+position
                }
                if solid == .cube,normal.filter({$0 != 0}).count == 1 {
                    let position=abs(plane.twiceOffset) == 4 ? "face":"interior"
                    return "cube.shape."+shape.rawValue+"."+position
                }
            }
            return solid.rawValue+"."+role+"."+(codes.min() ?? "invalid")
        }
    }
    static let tasks:[Task] = {
        var values:[Task]=[]
        for n in [(1,0,0),(1,1,0),(1,1,1),(2,1,0),(2,1,1)] {
            let limit=4*(n.0+n.1+n.2)+2
            for d in -limit...limit {
                let p=Plane(a:n.0,b:n.1,c:n.2,twiceOffset:d)
                values.append(.init(solid:.cube,plane:p,query:.classify))
            }
        }
        for n in [(0,0,1),(1,1,0),(1,1,1)] {
            for d in -12...12 {
                let p=Plane(a:n.0,b:n.1,c:n.2,twiceOffset:d),value=Task(solid:.sphere,plane:p,query:.classify)
                values.append(value)
                if value.shape == .circle { values.append(.init(solid:.sphere,plane:p,query:.sphereRadiusSquared)) }
            }
        }
        for n in [(0,0,1),(1,0,0),(1,0,1)] {
            for d in -12...12 { values.append(.init(solid:.cylinder,plane:.init(a:n.0,b:n.1,c:n.2,twiceOffset:d),query:.classify)) }
        }
        for d in [-12,-8,-4,0,4,8,12] {
            for shape in [Shape.triangle,.square,.hexagon] {
                for q in [Point.zero,.init(x:2,y:0,z:0)] {
                    values.append(.init(solid:.cube,plane:.init(a:1,b:1,c:1,twiceOffset:d),query:.verify(shape:shape,through:q)))
                }
            }
        }
        // Every authored parameter case remains testable; delivery selects one
        // representative per symmetry/query class, avoiding alias inflation.
        return values
    }()
    static let supportedTasks=Set(tasks)
    private static let identities:[Task:String] = Dictionary(tasks.map { ($0,$0.computedIdentity) },uniquingKeysWith:{ first,_ in first })
    static let representatives:[Task] = {
        var seen:Set<String>=[]
        return tasks.filter { $0.shape != nil && seen.insert($0.identity).inserted }
    }()
}


extension NFCubeNetEngine {
    /// All 35 free connected six-square proposals. Validity is a question for
    /// these layouts, never an assertion embedded in their description.
    static let canonicalProposals:[NFCubeNetLayout] = {
        var values:[String:[Coordinate]]=[:]
        for shape in enumerateConnectedHexominoes() {
            let canonical=canonicalFreeShape(shape);values[shapeKey(canonical)]=canonical
        }
        return values.keys.sorted().compactMap { key in values[key].map { cells in
            NFCubeNetLayout(cells:cells.enumerated().map { NFCubeNetCell(x:$0.element.x,y:$0.element.y,label:String(UnicodeScalar(65+$0.offset)!)) })
        } }
    }()
}

enum NFNetFoldingGeometry {
    struct Vector:Codable,Hashable,Sendable {
        let x:Int,y:Int,z:Int
        static let zero=Self(x:0,y:0,z:0)
        static let xAxis=Self(x:1,y:0,z:0),yAxis=Self(x:0,y:1,z:0),zAxis=Self(x:0,y:0,z:1)
        static prefix func - (v:Self)->Self { .init(x:-v.x,y:-v.y,z:-v.z) }
        static func + (a:Self,b:Self)->Self { .init(x:a.x+b.x,y:a.y+b.y,z:a.z+b.z) }
        static func - (a:Self,b:Self)->Self { a + (-b) }
        static func * (a:Self,b:Int)->Self { .init(x:a.x*b,y:a.y*b,z:a.z*b) }
        func dot(_ b:Self)->Int { x*b.x+y*b.y+z*b.z }
        var values:[Int] { [x,y,z] }
        var token:String { values.map(String.init).joined(separator:",") }
    }
    enum Direction:String,Codable,CaseIterable,Hashable,Sendable {
        case positiveX,negativeX,positiveY,negativeY,positiveZ,negativeZ
        var vector:Vector { switch self {
        case .positiveX:.xAxis;case .negativeX: -.xAxis;case .positiveY:.yAxis;case .negativeY: -.yAxis;case .positiveZ:.zAxis;case .negativeZ: -.zAxis } }
        var symbol:String { switch self { case .positiveX:"+x";case .negativeX:"−x";case .positiveY:"+y";case .negativeY:"−y";case .positiveZ:"+z";case .negativeZ:"−z" } }
    }
    struct Frame:Equatable,Sendable {
        let label:String
        /// Twice the center coordinate keeps every hinge endpoint exact.
        let center2:Vector,right:Vector,up:Vector,normal:Vector
        var corners2:[Vector] { [center2+right+up,center2+right-up,center2-right-up,center2-right+up] }
    }
    enum Component:String,Codable,Hashable,Sendable { case normal,printedArrow }
    enum Constraint:Codable,Hashable,Sendable {
        case opposite(String,String)
        case adjacent(String,String)
        case direction(String,Component,Direction)
        var roles:[String] { switch self { case let .opposite(a,b),let .adjacent(a,b):[a,b];case let .direction(a,_,_):[a] } }
    }
    enum Query:Codable,Hashable,Sendable {
        case validity
        case opposite(String)
        case adjacent(String)
        case direction(String,Component)
        case constraints(Constraint,Constraint)
    }
    struct Task:Codable,Equatable,Sendable {
        let layout:NFCubeNetLayout
        let query:Query
        /// The named leaf is folded 90 degrees away from the viewer in the
        /// original given; all other hinges remain flat. Empty means flat net.
        let givenFoldedLeaf:String?
        var bounded:Bool {
            guard layout.cells.count == 6,Set(layout.cells.map(\.label)) == Set(["A","B","C","D","E","F"]),
                  layout.cells.allSatisfy({(0...5).contains($0.x) && (0...5).contains($0.y)}),
                  Set(layout.cells.map{"\($0.x),\($0.y)"}).count == 6 else { return false }
            if let leaf=givenFoldedLeaf { guard Self.leaves(layout).contains(leaf),leaf != layout.cells.first?.label else{return false} }
            let labels=Set(layout.cells.map(\.label))
            switch query {
            case .validity:return givenFoldedLeaf == nil
            case let .opposite(a),let .adjacent(a),let .direction(a,_):return labels.contains(a) && NFCubeNetEngine.isValid(layout)
            case let .constraints(a,b):return a != b && (a.roles+b.roles).allSatisfy(labels.contains) && NFCubeNetEngine.isValid(layout)
            }
        }
        static func leaves(_ layout:NFCubeNetLayout)->[String] {
            layout.cells.filter { a in layout.cells.filter{abs($0.x-a.x)+abs($0.y-a.y)==1}.count == 1 }.map(\.label)
        }
        var validNet:Bool { bounded && NFCubeNetEngine.isValid(layout) }
        var completedFrames:[Frame]? { guard validNet else{return nil};return Self.frames(layout,folded:nil) }
        var originalFrames:[Frame]? { guard bounded else{return nil};return Self.frames(layout,folded:Set(givenFoldedLeaf.map{[$0]} ?? [])) }
        /// Tree hinges are rotated exactly, with each descendant following its
        /// parent. `nil` folds every hinge. Invalid proposals never get a
        /// completed cube; their original flat grid remains renderable.
        static func frames(_ layout:NFCubeNetLayout,folded:Set<String>?)->[Frame]? {
            guard layout.cells.count == 6,let root=layout.cells.first else{return nil}
            var frames:[String:Frame]=[root.label:.init(label:root.label,center2:.zero,right:.xAxis,up:.yAxis,normal:.zAxis)]
            var queue=[root],cursor=0
            while cursor<queue.count {
                let parent=queue[cursor];cursor+=1
                guard let f=frames[parent.label] else{return nil}
                for child in layout.cells where abs(child.x-parent.x)+abs(child.y-parent.y)==1 && frames[child.label] == nil {
                    let dx=child.x-parent.x,dy=child.y-parent.y,direction=f.right*dx+f.up*dy
                    let isFolded=folded == nil || folded!.contains(child.label)
                    let frame:Frame
                    if isFolded {
                        frame = .init(label:child.label,center2:f.center2+direction-f.normal,
                            right:dx == 0 ? f.right:f.normal*(-dx),up:dy == 0 ? f.up:f.normal*(-dy),normal:direction)
                    } else { frame = .init(label:child.label,center2:f.center2+direction*2,right:f.right,up:f.up,normal:f.normal) }
                    frames[child.label]=frame;queue.append(child)
                }
            }
            return frames.count == 6 ? layout.cells.compactMap{frames[$0.label]}:nil
        }
        func satisfies(_ value:Constraint)->Bool {
            guard let frames=completedFrames else{return false}
            func face(_ label:String)->Frame? {frames.first{$0.label==label}}
            switch value {
            case let .opposite(a,b):guard let x=face(a),let y=face(b) else{return false};return x.normal == -y.normal
            case let .adjacent(a,b):guard let x=face(a),let y=face(b) else{return false};return x.normal.dot(y.normal)==0
            case let .direction(a,c,d):guard let x=face(a) else{return false};return (c == .normal ? x.normal:x.up)==d.vector
            }
        }
        var acceptedIDs:Set<String> {
            guard bounded else{return []}
            switch query {
            case .validity:return [validNet ? "yes":"no"]
            case let .opposite(a):return Set(layout.cells.filter{satisfies(.opposite(a,$0.label))}.map(\.label))
            case let .adjacent(a):return Set(layout.cells.filter{satisfies(.adjacent(a,$0.label))}.map(\.label))
            case let .direction(a,c):return Set(Direction.allCases.filter{satisfies(.direction(a,c,$0))}.map(\.rawValue))
            case let .constraints(a,b):return [satisfies(a) && satisfies(b) ? "yes":"no"]
            }
        }
        /// Query roles are located on actual squares; arbitrary face names do
        /// not create another item. Coordinate-axis/arrow questions keep their
        /// declared frame instead of collapsing a reflection incorrectly.
        var deliveryIdentity:String {
            let form:String=switch query{case .validity:"validity";case .opposite:"opposite";case .adjacent:"adjacent";case .direction:"direction";case .constraints:"constraints"}
            return identity+".form:"+form
        }
        var identity:String {
            guard bounded else{return "invalid"}
            func point(_ label:String)->NFCubeNetCell?{layout.cells.first{$0.label==label}}
            let isOriented:Bool={switch query{case .direction:return true;case .constraints:return true;default:return false}}()
            func transform(_ c:NFCubeNetCell,_ t:Int)->(Int,Int){switch t{case 0:(c.x,c.y);case 1:(-c.y,c.x);case 2:(-c.x,-c.y);case 3:(c.y,-c.x);case 4:(-c.x,c.y);case 5:(c.x,-c.y);case 6:(c.y,c.x);default:(-c.y,-c.x)}}
            return (0..<(isOriented ? 1:8)).map { t in
                let positions=layout.cells.map{transform($0,t)},minX=positions.map(\.0).min()!,minY=positions.map(\.1).min()!
                func role(_ label:String)->String{guard let p=point(label) else{return "?"};let v=transform(p,t);return "\(v.0-minX),\(v.1-minY)"}
                let shape=positions.map{"\($0.0-minX),\($0.1-minY)"}.sorted().joined(separator:";")
                func constraint(_ c:Constraint)->String{switch c{case let .opposite(a,b):"opp:"+[role(a),role(b)].sorted().joined(separator:"/");case let .adjacent(a,b):"adj:"+[role(a),role(b)].sorted().joined(separator:"/");case let .direction(a,c,d):"dir:\(role(a)):\(c.rawValue):\(d.rawValue)"}}
                let q:String=switch query{case .validity:"validity";case let .opposite(a),let .adjacent(a):"face-relation:"+role(a);case let .direction(a,c):"direction:"+role(a)+":"+c.rawValue;case let .constraints(a,b):"constraints:"+[constraint(a),constraint(b)].sorted().joined(separator:"|")}
                return "net."+shape+"."+q+(isOriented ? ".anchor:"+role(layout.cells[0].label):"")+".given:"+(givenFoldedLeaf.map(role) ?? "flat")
            }.min()!
        }
    }
    static let tasks:[Task] = {
        var values=NFCubeNetEngine.canonicalProposals.map{Task(layout:$0,query:.validity,givenFoldedLeaf:nil)}
        for layout in NFCubeNetEngine.validCanonicalLayouts {
            let leaf=Task.leaves(layout).first{$0 != layout.cells.first?.label}
            for face in layout.cells {
                values.append(.init(layout:layout,query:.opposite(face.label),givenFoldedLeaf:nil))
                values.append(.init(layout:layout,query:.adjacent(face.label),givenFoldedLeaf:nil))
                if face.label != layout.cells.first?.label {
                    for component in [Component.normal,.printedArrow] {
                        values.append(.init(layout:layout,query:.direction(face.label,component),givenFoldedLeaf:leaf))
                    }
                }
            }
            let base=Task(layout:layout,query:.validity,givenFoldedLeaf:nil),labels=layout.cells.map(\.label)
            for a in labels.dropFirst() {
                let opposite=labels.first{base.satisfies(.opposite(a,$0))}!
                let up=Direction.allCases.first{base.satisfies(.direction(a,.printedArrow,$0))}!
                let wrong=Direction.allCases.first{$0.vector == -up.vector}!
                let adjacent=labels.first{$0 != a && base.satisfies(.adjacent(a,$0))}!
                for proposedFace in [opposite,adjacent] {for proposedDirection in [up,wrong] {
                    values.append(.init(layout:layout,query:.constraints(.opposite(a,proposedFace),.direction(a,.printedArrow,proposedDirection)),givenFoldedLeaf:nil))
                }}
            }
        }
        var seen:Set<String>=[]
        return values.filter{seen.insert($0.deliveryIdentity).inserted}
    }()
}


/// A separate ordinary recipe for inverse maps, identification from sufficient
/// correspondences, and scored orientation/fixed-locus reasoning. Forward-v12
/// tasks and their identities are not reinterpreted.
enum NFCoordinateReasoningGeometry {
    typealias Point = NFCoordinateTransformGeometry.Point
    typealias Operation = NFCoordinateTransformGeometry.Operation
    typealias Affine = NFCoordinateTransformGeometry.Affine
    enum Query: String, Codable, CaseIterable, Equatable, Sendable { case inverse, inferAffine, orientationFixed }
    enum FixedLocus: String, Codable, CaseIterable, Equatable, Sendable { case none, point, line, plane }
    struct Pair: Codable, Equatable, Sendable { let source: Point; let target: Point }
    struct Task: Codable, Equatable, Sendable {
        let query: Query
        let familyVariant: Int
        let originals: [Point]
        let operations: [Operation]
        var map: Affine? {
            guard (1...3).contains(operations.count), operations.allSatisfy(\.isBounded) else { return nil }
            return operations.reduce(Affine.identity) { $1.affine!.after($0) }
        }
        var isBounded: Bool {
            guard [0,5].contains(familyVariant), originals.count == (query == .inverse ? 1 : 3),
                  originals.allSatisfy(\.isBounded), let map, [-1,1].contains(map.determinant),
                  query != .orientationFixed || familyVariant == 5,
                  query != .inferAffine || familyVariant == 0,
                  query == .inverse || NFCoordinateReasoningGeometry.area2(originals) != 0 else { return false }
            for point in originals {
                var current = point
                for operation in operations {
                    current = operation.affine!.applying(current)
                    guard current.isBounded else { return false }
                }
            }
            return query != .inferAffine || NFCoordinateReasoningGeometry.solve(pairs: pairs) == map
        }
        var pairs: [Pair] { guard let map, originals.count <= 3, originals.allSatisfy(\.isBounded) else { return [] }; return originals.map { .init(source:$0,target:map.applying($0)) } }
        var orientationPreserved: Bool { map?.determinant == 1 }
        var fixedLocus: FixedLocus? { map.map(NFCoordinateReasoningGeometry.fixedLocus) }
        var exactValues: [String:String] {
            guard isBounded else { return [:] }
            switch query {
            case .inverse: return ["x":String(originals[0].x),"y":String(originals[0].y)]
            case .inferAffine:
                guard let value = NFCoordinateReasoningGeometry.solve(pairs:pairs) else { return [:] }
                return ["a":String(value.a),"b":String(value.b),"c":String(value.c),"d":String(value.d),"tx":String(value.tx),"ty":String(value.ty)]
            case .orientationFixed: return [:]
            }
        }
        /// Signed, translated and uniformly scaled copies are delivery variants,
        /// not independent structures. Conjugate the complete requested map and
        /// its original givens together under D4, then normalize common scale.
        var identity: String {
            guard isBounded else { return "unavailable" }
            let axes = [Affine(a:1,b:0,c:0,d:1,tx:0,ty:0), .init(a:0,b:-1,c:1,d:0,tx:0,ty:0),
                .init(a:-1,b:0,c:0,d:-1,tx:0,ty:0), .init(a:0,b:1,c:-1,d:0,tx:0,ty:0),
                .init(a:-1,b:0,c:0,d:1,tx:0,ty:0), .init(a:1,b:0,c:0,d:-1,tx:0,ty:0),
                .init(a:0,b:1,c:1,d:0,tx:0,ty:0), .init(a:0,b:-1,c:-1,d:0,tx:0,ty:0)]
            let origin = query == .inferAffine ? originals[0] : operations[0].anchor
            // The classification is global: changing only the illustrative
            // noncollinear triangle never creates another orientation/fixed-set target.
            let normalized = query == .orientationFixed ? [] : originals.map { Point(x:$0.x-origin.x,y:$0.y-origin.y) }
            let maps = operations.compactMap(\.affine).map { f in Affine(a:f.a,b:f.b,c:f.c,d:f.d,
                tx:f.a*origin.x+f.b*origin.y+f.tx-origin.x,ty:f.c*origin.x+f.d*origin.y+f.ty-origin.y) }
            let candidates = axes.map { s -> String in
                let inverse = Affine(a:s.a,b:s.c,c:s.b,d:s.d,tx:0,ty:0)
                let points = normalized.map(s.applying), moves = maps.map { s.after($0).after(inverse) }
                // Unknown-map tasks cannot gain novelty from an unseen recipe
                // decomposition. The final map and visible correspondences own it.
                let effective = query == .inferAffine ? [moves.reduce(Affine.identity) { $1.after($0) }] : moves
                let scalars = points.flatMap { [$0.x,$0.y] } + effective.flatMap { [$0.tx,$0.ty] }
                let divisor = max(1,scalars.reduce(0) { gcd($0,abs($1)) })
                return (points.flatMap { [$0.x/divisor,$0.y/divisor] } + effective.flatMap { [$0.a,$0.b,$0.c,$0.d,$0.tx/divisor,$0.ty/divisor] }).map(String.init).joined(separator:",")
            }
            return "coordinate-reasoning.\(query.rawValue).\(familyVariant)." + (candidates.min() ?? "unavailable")
        }
    }
    static func area2(_ points:[Point])->Int {
        guard points.count == 3,points.allSatisfy(\.isBounded) else { return 0 }
        return (points[1].x-points[0].x)*(points[2].y-points[0].y)-(points[1].y-points[0].y)*(points[2].x-points[0].x)
    }
    /// Exact affine interpolation through three noncollinear points. The
    /// admitted family has integer coefficients; nonintegral/ambiguous payloads
    /// are unavailable rather than rounded to a guessed answer.
    static func solve(pairs:[Pair])->Affine? {
        guard pairs.count == 3,pairs.allSatisfy({$0.source.isBounded && $0.target.isBounded}) else { return nil }
        let p=pairs.map(\.source),q=pairs.map(\.target),det=area2(p)
        guard det != 0 else { return nil }
        let ux=p[1].x-p[0].x,uy=p[1].y-p[0].y,vx=p[2].x-p[0].x,vy=p[2].y-p[0].y
        let x1=q[1].x-q[0].x,x2=q[2].x-q[0].x,y1=q[1].y-q[0].y,y2=q[2].y-q[0].y
        let numerators=[x1*vy-x2*uy,ux*x2-vx*x1,y1*vy-y2*uy,ux*y2-vx*y1]
        guard numerators.allSatisfy({$0 % det == 0}) else { return nil }
        let values=numerators.map{$0/det},a=values[0],b=values[1],c=values[2],d=values[3]
        let result=Affine(a:a,b:b,c:c,d:d,tx:q[0].x-a*p[0].x-b*p[0].y,ty:q[0].y-c*p[0].x-d*p[0].y)
        return pairs.allSatisfy{result.applying($0.source)==$0.target} ? result:nil
    }
    static func fixedLocus(_ f:Affine)->FixedLocus {
        let a=f.a-1,b=f.b,c=f.c,d=f.d-1,u = -f.tx,v = -f.ty
        if a*d-b*c != 0 { return .point }
        if a == 0 && b == 0 && c == 0 && d == 0 { return u == 0 && v == 0 ? .plane:.none }
        return a*v-c*u == 0 && b*v-d*u == 0 ? .line:.none
    }
    private static func gcd(_ a:Int,_ b:Int)->Int { var x=a,y=b;while y != 0 { let r=x%y;x=y;y=r };return x }
    static let tasks:[Task] = {
        let zero=Point(x:0,y:0),center=Point(x:1,y:-1),translation=Point(x:2,y:1)
        let rotationRecipes:[[Operation]] = [
            [.rotate(center:zero,quarterTurns:1)], [.rotate(center:zero,quarterTurns:-1)], [.rotate(center:zero,quarterTurns:2)],
            [.rotate(center:center,quarterTurns:1)], [.rotate(center:center,quarterTurns:-1)],
            [.translate(vector:translation),.rotate(center:center,quarterTurns:1)],
            [.rotate(center:center,quarterTurns:1),.translate(vector:translation)],
            [.rotate(center:zero,quarterTurns:1),.rotate(center:center,quarterTurns:-1)]]
        let reflectionRecipes:[[Operation]] = [
            [.reflect(line:.vertical,offset:0)], [.reflect(line:.horizontal,offset:-1)], [.reflect(line:.risingDiagonal,offset:0)],
            [.reflect(line:.fallingDiagonal,offset:0)], [.reflect(line:.vertical,offset:1),.reflect(line:.vertical,offset:1)],
            [.reflect(line:.vertical,offset:0),.reflect(line:.vertical,offset:1)],
            [.reflect(line:.vertical,offset:1),.reflect(line:.horizontal,offset:-1)],
            [.reflect(line:.vertical,offset:0),.reflect(line:.risingDiagonal,offset:0)],
            [.rotate(center:center,quarterTurns:1),.reflect(line:.risingDiagonal,offset:0)],
            [.reflect(line:.risingDiagonal,offset:0),.rotate(center:center,quarterTurns:1)],
            [.reflect(line:.horizontal,offset:0),.translate(vector:translation)]]
        var result:[Task]=[]
        for (variant,recipes) in [(0,rotationRecipes),(5,reflectionRecipes)] {
            for operations in recipes {
                for point in NFCoordinateTransformGeometry.sourcePoints {
                    result.append(.init(query:.inverse,familyVariant:variant,originals:[point],operations:operations))
                }
            }
        }
        let triangles:[[Point]] = [[zero,.init(x:2,y:0),.init(x:0,y:3)],
            [.init(x:-3,y:-2),.init(x:-1,y:-2),.init(x:-3,y:1)],
            [.init(x:0,y:0),.init(x:0,y:-2),.init(x:3,y:0)]]
        for operations in rotationRecipes { for triangle in triangles {
            result.append(.init(query:.inferAffine,familyVariant:0,originals:triangle,operations:operations))
        }}
        let orientationTriangles=triangles+[[zero,Point(x:0,y:3),Point(x:2,y:0)]]
        for operations in reflectionRecipes { for triangle in orientationTriangles {
            result.append(.init(query:.orientationFixed,familyVariant:5,originals:triangle,operations:operations))
        }}
        return result.filter(\.isBounded)
    }()
}

/// Bounded physical occupied-cell questions. Hidden candidate cells are never
/// authority for rejecting a visually equivalent, feasible proper orientation.
enum NFSpatialAssemblyGeometry {
    typealias Cell = NFSpatialStructureGeometry.Cell
    typealias Square = NFSpatialStructureGeometry.Square
    struct Rotation: Codable, Equatable, Hashable, Sendable {
        let axes: [Int]
        let signs: [Int]
        var determinant: Int {
            guard axes.count == 3, Set(axes) == Set(0..<3), signs.count == 3, signs.allSatisfy({ [-1,1].contains($0) }) else { return 0 }
            let inversions = (0..<3).reduce(0) { n,i in n + ((i+1)..<3).filter { axes[i] > axes[$0] }.count }
            return (inversions % 2 == 0 ? 1:-1) * signs.reduce(1,*)
        }
        func apply(_ cells: [Cell]) -> [Cell] {
            guard determinant == 1, permits(cells) else { return [] }
            return normalized(cells.map { c in
                let v=[c.x,c.y,c.z]
                return Cell(x:signs[0]*v[axes[0]],y:signs[1]*v[axes[1]],z:signs[2]*v[axes[2]])
            })
        }
        var token: String { zip(axes,signs).map { "\($0):\($1)" }.joined(separator:",") }
    }
    static let rotations: [Rotation] = {
        let permutations = [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]]
        return permutations.flatMap { axes in [-1,1].flatMap { x in [-1,1].flatMap { y in [-1,1].map { z in Rotation(axes:axes,signs:[x,y,z]) } } } }.filter { $0.determinant == 1 }
    }()
    struct Views: Codable, Equatable, Hashable, Sendable {
        let front: [Square]
        let side: [Square]
        var isBounded: Bool {
            [front,side].allSatisfy { !$0.isEmpty && $0.count <= 12 && $0 == Set($0).sorted()
                && $0.allSatisfy { (0...3).contains($0.x) && (0...3).contains($0.y) } }
        }
        var token: String { front.map(\.token).joined(separator:";")+"/"+side.map(\.token).joined(separator:";") }
    }
    struct Orientation: Codable, Equatable, Sendable {
        let source: [Cell]
        let candidates: [[Cell]]
        var shown: [Views] { candidates.map(views) }
        var properViews: Set<Views> { Set(rotations.map { views($0.apply(source)) }) }
        var acceptedIndices: [Int] { shown.indices.filter { properViews.contains(shown[$0]) } }
        var isBounded: Bool {
            guard permits(source),source.count == 5,source == normalized(source),candidates.count == 4,
                  candidates.allSatisfy({ permits($0) && $0.count == 5 && $0 == normalized($0) }),
                  Set(rotations.map { $0.apply(source) }).count == 24,
                  !Set(rotations.map { $0.apply(source) }).contains(mirrored(source)),
                  shown.allSatisfy(\.isBounded), Set(shown).count == candidates.count,
                  shown.allSatisfy({ $0.front.count < 5 || $0.side.count < 5 }),
                  (1...3).contains(acceptedIndices.count) else { return false }
            // Every candidate is a proper or improper orientation of this real
            // solid, and mirror-only claims require distinguishing public views.
            let proper = Set(rotations.map { $0.apply(source) })
            let mirrors = Set(rotations.map { $0.apply(mirrored(source)) })
            return candidates.enumerated().allSatisfy { i,c in
                proper.contains(c) || (mirrors.contains(c) && !properViews.contains(shown[i]))
            }
        }
        var identity: String {
            // Source pose, option shuffling and target orientation variants do
            // not inflate the same proper-versus-mirror reasoning target.
            let shape = rotations.map { $0.apply(source).map(\.token).joined(separator:";") }.min() ?? ""
            let reflected = rotations.map { $0.apply(mirrored(source)).map(\.token).joined(separator:";") }.min() ?? ""
            return "orientation." + min(shape,reflected)
        }
        func matchingRotation(for index:Int)->Rotation? {
            guard candidates.indices.contains(index) else { return nil }
            return rotations.first { views($0.apply(source)) == shown[index] }
        }
    }
    struct Constraints: Codable, Equatable, Hashable, Sendable {
        let top: [Bool]
        let front: [Int]
        let side: [Int]
        let cubeCount: Int
        var isBounded: Bool { top.count == 4 && front.count == 2 && side.count == 2
            && (front+side).allSatisfy { (0...3).contains($0) } && (1...12).contains(cubeCount) }
        func accepts(_ h:[Int])->Bool { isBounded && validHeights(h) && constraint(for:h) == self }
        var feasible: [[Int]] { guard isBounded else { return [] };return heightMaps.filter(accepts) }
        var token: String { top.map { $0 ? "1":"0" }.joined()+"/"+front.map(String.init).joined()+"/"+side.map(String.init).joined()+"/"+String(cubeCount) }
        var identity: String {
            // Swap/reverse the two fixed horizontal axes jointly across all
            // supplied views. Renaming an axis or rotating the diagram is not novelty.
            (0..<8).map { transformConstraints(self,symmetry:$0).token }.min() ?? token
        }
    }
    struct Reconstruction: Codable, Equatable, Sendable {
        let constraints: Constraints
        let candidates: [[Int]]
        var feasible: [[Int]] { constraints.feasible }
        var acceptedIndices: [Int] { candidates.indices.filter { constraints.accepts(candidates[$0]) } }
        var isBounded: Bool {
            constraints.isBounded && candidates.count == 8 && Set(candidates).count == 8
                && candidates.allSatisfy(validHeights) && feasible.count <= 6
                && Set(feasible).isSubset(of:Set(candidates))
        }
        var identity: String { "reconstruction."+constraints.identity }
    }
    enum Task: Codable, Equatable, Sendable {
        case orientation(Orientation), reconstruction(Reconstruction)
        var variant: Int { if case .orientation = self { return 1 };return 3 }
        var isBounded: Bool { switch self {case let .orientation(v):v.isBounded;case let .reconstruction(v):v.isBounded} }
        var identity: String { switch self {case let .orientation(v):v.identity;case let .reconstruction(v):v.identity} }
        var acceptedIndices: [Int] { switch self {case let .orientation(v):v.acceptedIndices;case let .reconstruction(v):v.acceptedIndices} }
        var candidateCount: Int { switch self {case let .orientation(v):v.candidates.count;case let .reconstruction(v):v.candidates.count} }
        var impossible: Bool { if case let .reconstruction(v)=self {return v.feasible.isEmpty};return false }
    }
    static func permits(_ cells:[Cell])->Bool {
        guard !cells.isEmpty,cells.count <= 12,Set(cells).count == cells.count,
              cells.allSatisfy({ (0...3).contains($0.x) && (0...3).contains($0.y) && (0...3).contains($0.z) }) else { return false }
        let occupied=Set(cells);var reached:Set<Cell>=[cells[0]],frontier=[cells[0]]
        while let c=frontier.popLast() {
            for delta in [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)] {
                let n=Cell(x:c.x+delta.0,y:c.y+delta.1,z:c.z+delta.2)
                if occupied.contains(n),reached.insert(n).inserted {frontier.append(n)}
            }
        }
        return reached.count == cells.count
    }
    static func normalized(_ cells:[Cell])->[Cell] {
        guard !cells.isEmpty,cells.count <= 12 else { return [] }
        // Inputs are validated before signed transforms; the additional scalar
        // guard also makes direct malformed decode probes safe.
        guard cells.allSatisfy({ (-4...4).contains($0.x) && (-4...4).contains($0.y) && (-4...4).contains($0.z) }) else {return []}
        let x=cells.map(\.x).min()!,y=cells.map(\.y).min()!,z=cells.map(\.z).min()!
        return cells.map{Cell(x:$0.x-x,y:$0.y-y,z:$0.z-z)}.sorted()
    }
    static func mirrored(_ cells:[Cell])->[Cell] { guard permits(cells) else {return []};return normalized(cells.map {Cell(x:-$0.x,y:$0.y,z:$0.z)}) }
    static func views(_ cells:[Cell])->Views {
        guard permits(cells) else { return .init(front:[],side:[]) }
        return .init(front:Set(cells.map{Square(x:$0.x,y:$0.z)}).sorted(),side:Set(cells.map{Square(x:$0.y,y:$0.z)}).sorted())
    }
    static func validHeights(_ h:[Int])->Bool { h.count == 4 && h.allSatisfy{(0...3).contains($0)} && permits(cells(heights:h)) }
    static func cells(heights:[Int])->[Cell] {
        guard heights.count == 4,heights.allSatisfy({(0...3).contains($0)}) else {return []}
        return heights.enumerated().flatMap { i,n in (0..<n).map{Cell(x:i%2,y:i/2,z:$0)} }.sorted()
    }
    static let heightMaps:[[Int]] = (0..<256).map { n in [n%4,(n/4)%4,(n/16)%4,(n/64)%4] }.filter(validHeights)
    static func constraint(for h:[Int])->Constraints {
        guard validHeights(h) else { return .init(top:[],front:[],side:[],cubeCount:0) }
        return .init(top:h.map{$0>0},front:[max(h[0],h[2]),max(h[1],h[3])],side:[max(h[0],h[1]),max(h[2],h[3])],cubeCount:h.reduce(0,+))
    }
    static func gridTransform(_ index:Int,symmetry:Int)->Int {
        let x=index%2,y=index/2
        switch symmetry {case 0:return y*2+x;case 1:return x*2+(1-y);case 2:return (1-y)*2+(1-x);case 3:return (1-x)*2+y;case 4:return y*2+(1-x);case 5:return (1-y)*2+x;case 6:return x*2+y;default:return (1-x)*2+(1-y)}
    }
    static func transformConstraints(_ c:Constraints,symmetry:Int)->Constraints {
        guard c.isBounded else{return c}
        var top=Array(repeating:false,count:4)
        for i in 0..<4{top[gridTransform(i,symmetry:symmetry)]=c.top[i]}
        // Transform each axis-aligned column-bound ray without choosing any
        // hidden reconstruction, so impossible sets canonicalize faithfully too.
        var front=Array(repeating:0,count:2),side=front
        for axis in 0..<2 {for value in 0..<2 {
            let ray=(0..<4).filter{axis == 0 ? $0%2==value:$0/2==value}.map{gridTransform($0,symmetry:symmetry)}
            let h=axis == 0 ? c.front[value]:c.side[value]
            if ray[0]%2 == ray[1]%2 {front[ray[0]%2]=h}else{side[ray[0]/2]=h}
        }}
        return .init(top:top,front:front,side:side,cubeCount:c.cubeCount)
    }
    static let sources:[[Cell]] = [
        [(0,0,0),(0,0,1),(0,0,2),(0,1,0),(1,0,1)],
        [(0,0,0),(0,0,1),(0,0,2),(0,1,0),(1,1,0)],
        [(0,0,0),(0,0,1),(0,1,0),(1,0,1),(1,0,2)],
        [(0,0,0),(0,0,1),(0,1,1),(0,1,2),(1,0,1)]
    ].map{$0.map{Cell(x:$0.0,y:$0.1,z:$0.2)}.sorted()}
    @inline(never)
    static func orientationTasks()->[Task] {
        var tasks:[Task]=[]
        for source in sources {
            let proper=rotations.map{$0.apply(source)},good=Set(proper.map(views))
            let reflected=rotations.map{$0.apply(mirrored(source))}.filter{!good.contains(views($0))}
            for start in 0..<min(proper.count,reflected.count) {
                let count=start%3+1
                var candidates=Array((0..<count).map{proper[(start+$0)%proper.count]})
                candidates += (0..<(4-count)).map{reflected[(start+$0)%reflected.count]}
                let shift=start%4;candidates=Array(candidates.dropFirst(shift))+Array(candidates.prefix(shift))
                let v=Orientation(source:source,candidates:candidates)
                if v.isBounded {tasks.append(.orientation(v))}
            }
        }
        return tasks
    }
    @inline(never)
    static func reconstructionTasks()->[Task] {
        var constraints=Set(heightMaps.map(constraint))
        // Deliberate inconsistent total count preserves all other supplied rays.
        for original in Array(constraints) {
            let impossible=Constraints(top:original.top,front:original.front,side:original.side,cubeCount:12)
            if impossible.feasible.isEmpty {constraints.insert(impossible)}
        }
        var result:[Task]=[],seen:Set<String>=[]
        for c in constraints.sorted(by:{$0.token<$1.token}) where seen.insert(c.identity).inserted {
            let matches=c.feasible
            guard matches.count <= 6 else {continue}
            let wrong=heightMaps.filter{!c.accepts($0)}
            var candidates=matches+Array(wrong.prefix(8-matches.count))
            let shift=c.cubeCount%8;candidates=Array(candidates.dropFirst(shift))+Array(candidates.prefix(shift))
            let v=Reconstruction(constraints:c,candidates:candidates)
            if v.isBounded {result.append(.reconstruction(v))}
        }
        return result
    }
    static let tasks:[Task] = orientationTasks()+reconstructionTasks()
}
