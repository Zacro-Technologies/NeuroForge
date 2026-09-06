import Foundation

struct NFContentAdmissionCandidate: Codable, Equatable, Sendable {
    let semanticProblemID: String
    let semanticFingerprint: String
    let fieldID: String
    let structureID: String
    let compatibleFamilyIDs: [String]
    let availableAssetIDs: [String]
    let requiredAssetIDs: [String]
    let supportedLocaleIDs: [String]
    let valid: Bool
}

struct NFContentAdmissionPolicy: Codable, Equatable, Sendable {
    var version = 1
    let quotasByFamilyID: [String: Int]
    var quotasByFieldID: [String: Int] = [:]
    var maximumPerFamilyStructure: [String: Int] = [:]
    var minimumStructuresPerFamily: [String: Int] = [:]
    var requiredLocaleIDs: [String] = ["en", "ja"]
}

struct NFContentAdmissionAssignment: Codable, Equatable, Sendable {
    let semanticProblemID: String
    let semanticFingerprint: String
    let fieldID: String
    let structureID: String
    let familyID: String
}

struct NFContentAdmissionDeficit: Codable, Equatable, Sendable {
    let dimension: String
    let identifier: String
    let required: Int
    let available: Int
    let assigned: Int
}

struct NFContentAdmissionReport: Codable, Equatable, Sendable {
    let policyVersion: Int
    let assignments: [NFContentAdmissionAssignment]
    let deficits: [NFContentAdmissionDeficit]
    let rejectedByReason: [String: Int]
    var isFeasible: Bool { deficits.isEmpty }
}

/// Deterministic finite assignment with one unit of capacity per semantic
/// problem. A target that supports several renderings can occupy only one
/// edition slot. No absent equation or translated asset is synthesized.
enum NFContentAdmission {
    static func assign(_ input: [NFContentAdmissionCandidate], policy: NFContentAdmissionPolicy) -> NFContentAdmissionReport {
        var rejected: [String: Int] = [:]
        var seen: Set<String> = []
        var seenFingerprints: Set<String> = []
        let candidates = input.sorted { ($0.semanticProblemID, $0.semanticFingerprint) < ($1.semanticProblemID, $1.semanticFingerprint) }.filter { candidate in
            let reason: String?
            if !candidate.valid { reason = "invalidContract" }
            else if !Set(candidate.requiredAssetIDs).isSubset(of: Set(candidate.availableAssetIDs)) { reason = "missingAsset" }
            else if !Set(policy.requiredLocaleIDs).isSubset(of: Set(candidate.supportedLocaleIDs)) { reason = "unsupportedLocale" }
            else if candidate.semanticProblemID.isEmpty || candidate.semanticFingerprint.isEmpty || candidate.structureID.isEmpty { reason = "missingIdentity" }
            else if seen.contains(candidate.semanticProblemID) || seenFingerprints.contains(candidate.semanticFingerprint) { reason = "duplicateSemanticProblem" }
            else { reason = nil }
            if let reason { rejected[reason, default: 0] += 1; return false }
            seen.insert(candidate.semanticProblemID); seenFingerprints.insert(candidate.semanticFingerprint)
            return true
        }
        let total = policy.quotasByFamilyID.values.reduce(0, +)
        guard total > 0, policy.quotasByFamilyID.values.allSatisfy({ $0 >= 0 }),
              policy.quotasByFieldID.values.allSatisfy({ $0 >= 0 }),
              policy.maximumPerFamilyStructure.values.allSatisfy({ $0 > 0 }),
              policy.minimumStructuresPerFamily.values.allSatisfy({ $0 >= 0 }),
              policy.quotasByFieldID.isEmpty || policy.quotasByFieldID.values.reduce(0, +) == total else {
            return NFContentAdmissionReport(policyVersion: policy.version, assignments: [],
                deficits: [NFContentAdmissionDeficit(dimension: "policy", identifier: "quotaTotals", required: max(0, total), available: 0, assigned: 0)], rejectedByReason: rejected)
        }
        var graph = FlowGraph()
        let source = graph.node("source"), sink = graph.node("sink")
        let families = policy.quotasByFamilyID.keys.sorted()
        for family in families {
            graph.add(graph.node("family:" + family), sink, capacity: policy.quotasByFamilyID[family] ?? 0)
            if let minimum = policy.minimumStructuresPerFamily[family], minimum > 0 {
                graph.add(graph.node("coverage:" + family), graph.node("family:" + family), capacity: minimum)
            }
        }
        for field in Set(candidates.map(\.fieldID)).sorted() {
            let capacity = policy.quotasByFieldID.isEmpty ? total : (policy.quotasByFieldID[field] ?? 0)
            graph.add(source, graph.node("field:" + field), capacity: capacity)
        }
        var candidateEdges: [(Int, Int, Int, String)] = []
        var addedStructureEdges: Set<String> = []
        for (index, candidate) in candidates.enumerated() {
            let node = graph.node("candidate:\(index)")
            graph.add(graph.node("field:" + candidate.fieldID), node, capacity: 1)
            for family in Set(candidate.compatibleFamilyIDs).sorted() where policy.quotasByFamilyID[family] != nil {
                let structureKey = family + "\u{0}" + candidate.structureID
                let structure = graph.node("structure:" + structureKey)
                if addedStructureEdges.insert(structureKey).inserted {
                    let gate = graph.node("structure-cap:" + structureKey)
                    let maximum = policy.maximumPerFamilyStructure[family] ?? total
                    graph.add(structure, gate, capacity: maximum)
                    graph.add(gate, graph.node("family:" + family), capacity: maximum)
                    if (policy.minimumStructuresPerFamily[family] ?? 0) > 0 {
                        // Reward only the first assigned item in each structure,
                        // with the family reward bounded at its required variety.
                        // Minimizing cost therefore satisfies every achievable
                        // family minimum while retaining exact quota flow.
                        graph.add(gate, graph.node("coverage:" + family), capacity: 1, cost: -1)
                    }
                }
                let edge = graph.add(node, structure, capacity: 1)
                candidateEdges.append((index, node, edge, family))
            }
        }
        graph.maximize(source: source, sink: sink)
        let assignments = candidateEdges.compactMap { index, node, edge, family -> NFContentAdmissionAssignment? in
            guard graph.edges[node][edge].capacity == 0 else { return nil }
            let candidate = candidates[index]
            return NFContentAdmissionAssignment(semanticProblemID: candidate.semanticProblemID,
                semanticFingerprint: candidate.semanticFingerprint, fieldID: candidate.fieldID,
                structureID: candidate.structureID, familyID: family)
        }
        var deficits: [NFContentAdmissionDeficit] = []
        for family in families {
            let required = policy.quotasByFamilyID[family] ?? 0
            let available = candidates.filter { $0.compatibleFamilyIDs.contains(family) }.count
            let delivered = assignments.filter { $0.familyID == family }
            if delivered.count < required {
                deficits.append(NFContentAdmissionDeficit(dimension: "family", identifier: family, required: required, available: available, assigned: delivered.count))
            }
            if let minimum = policy.minimumStructuresPerFamily[family] {
                let availableStructures = Set(candidates.filter { $0.compatibleFamilyIDs.contains(family) }.map(\.structureID)).count
                let assignedStructures = Set(delivered.map(\.structureID)).count
                if assignedStructures < minimum {
                    deficits.append(NFContentAdmissionDeficit(dimension: "structure", identifier: family, required: minimum, available: availableStructures, assigned: assignedStructures))
                }
            }
        }
        for field in policy.quotasByFieldID.keys.sorted() {
            let required = policy.quotasByFieldID[field] ?? 0
            let assigned = assignments.filter { $0.fieldID == field }.count
            if assigned < required {
                deficits.append(NFContentAdmissionDeficit(dimension: "field", identifier: field, required: required,
                    available: candidates.filter { $0.fieldID == field }.count, assigned: assigned))
            }
        }
        return NFContentAdmissionReport(policyVersion: policy.version, assignments: assignments, deficits: deficits, rejectedByReason: rejected)
    }

    static func proposedEditionPolicy(for lab: TrainingLab) -> NFContentAdmissionPolicy {
        let activities = NFDefaultContentCatalog.activities.filter { $0.lab == lab }
        let quotas: [Int] = switch lab {
        case .mentalMath: Array(repeating: 100, count: 10)
        case .spatial: [167, 167, 167, 167, 166, 166]
        case .quantitative: Array(repeating: 125, count: 8)
        case .scientificReasoning, .logicDebugging: [112] + Array(repeating: 111, count: 8)
        case .retrieval: [100, 160, 140, 100, 120, 20, 140, 100, 20]
        case .transfer: [143, 143, 143, 143, 143, 143, 142]
        }
        var policy = NFContentAdmissionPolicy(quotasByFamilyID: Dictionary(uniqueKeysWithValues: zip(activities.map(\.id), quotas)))
        if lab == .retrieval { policy.quotasByFieldID = Dictionary(uniqueKeysWithValues: STEMField.allCases.map { ($0.rawValue, 125) }) }
        if [.mentalMath, .quantitative, .transfer].contains(lab) {
            policy.maximumPerFamilyStructure = Dictionary(uniqueKeysWithValues: zip(activities.map(\.id), quotas.map { $0 / 2 }))
        }
        if lab == .mentalMath { policy.minimumStructuresPerFamily = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, 4) }) }
        return policy
    }

    private struct FlowGraph {
        struct Edge { let to: Int; let reverse: Int; var capacity: Int; let cost: Int }
        var ids: [String: Int] = [:]
        var edges: [[Edge]] = []
        mutating func node(_ name: String) -> Int {
            if let id = ids[name] { return id }
            let id = edges.count; ids[name] = id; edges.append([]); return id
        }
        @discardableResult mutating func add(_ from: Int, _ to: Int, capacity: Int, cost: Int = 0) -> Int {
            let index = edges[from].count, reverse = edges[to].count
            edges[from].append(Edge(to: to, reverse: reverse, capacity: capacity, cost: cost))
            edges[to].append(Edge(to: from, reverse: index, capacity: 0, cost: -cost))
            return index
        }
        mutating func maximize(source: Int, sink: Int) {
            while true {
                var parent = Array(repeating: (-1, -1), count: edges.count)
                var distance = Array(repeating: Int.max, count: edges.count)
                var queued = Array(repeating: false, count: edges.count)
                var queue = [source], cursor = 0
                distance[source] = 0; queued[source] = true
                // Successive shortest augmenting paths include reverse edges,
                // so a shared target can be reassigned to repair both quota and
                // variety conflicts. Initial network is acyclic; shortest-path
                // augmentation preserves absence of negative residual cycles.
                while cursor < queue.count {
                    let from = queue[cursor]; cursor += 1; queued[from] = false
                    for (index, edge) in edges[from].enumerated() where edge.capacity > 0 {
                        let proposed = distance[from] + edge.cost
                        if proposed < distance[edge.to] {
                            distance[edge.to] = proposed; parent[edge.to] = (from, index)
                            if !queued[edge.to] { queue.append(edge.to); queued[edge.to] = true }
                        }
                    }
                }
                if parent[sink].0 == -1 { return }
                var to = sink
                while to != source {
                    let (from, index) = parent[to]
                    let reverse = edges[from][index].reverse
                    edges[from][index].capacity -= 1
                    edges[to][reverse].capacity += 1
                    to = from
                }
            }
        }
    }
}
