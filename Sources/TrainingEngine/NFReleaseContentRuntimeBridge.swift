import Foundation

/// Connects the signed descriptor inventory to the concrete runtime catalogs.
/// These checks prevent a valid release manifest from masking an accidentally
/// truncated generator bank in the compiled app.
enum NFReleaseContentRuntimeBridge {
    static func audit() -> [String] {
        var violations: [String] = []

        let runtimePacks = NFMentalMathDomainPackCatalog.packs
        if runtimePacks.count != 4 || runtimePacks.contains(where: { $0.templates.count != 60 }) {
            violations.append("runtime-mental-pack-shape")
        }
        let runtimeTemplateIDs = Set(runtimePacks.flatMap(\.templates).map(\.id))
        let releaseTemplateIDs = Set(
            NFReleaseContentCatalog.inventory
                .collection(.mentalMathPackTemplates)?
                .descriptors.map(\.id) ?? []
        )
        if runtimeTemplateIDs != releaseTemplateIDs {
            violations.append("runtime-mental-template-identity")
        }

        let releaseMechanics = Set(
            NFReleaseContentCatalog.inventory
                .collection(.mentalMathMechanics)?
                .descriptors.map(\.family) ?? []
        )
        let runtimeMechanics = Set(runtimePacks.flatMap(\.templates).map(\.operationFamily))
        if runtimeMechanics != releaseMechanics {
            violations.append("runtime-mental-mechanic-coverage")
        }

        if NFCubeNetEngine.validCanonicalLayouts.count != 11 {
            violations.append("runtime-cube-net-catalog")
        }

        let baselineCandidateCount = NFAssessmentBlockKind.allCases.reduce(into: 0) { count, block in
            count += NFAssessmentEngine.makeBlockSession(
                block: block,
                phase: .initialBaseline,
                profileSeed: 0x4E46_5243
            ).candidatePool.count
        }
        if baselineCandidateCount < 120 {
            violations.append("runtime-baseline-candidate-minimum")
        }

        let releaseEvidenceLabs = Set(
            NFReleaseContentCatalog.inventory
                .collection(.evidenceCards)?
                .descriptors
                .filter { $0.attributes["claimScope"] == "in-app-evidence-only" }
                .map(\.family) ?? []
        )
        let expectedLabCards = Set([
            "mental-math", "spatial", "quantitative", "scientific-reasoning",
            "logic-debugging", "retrieval", "transfer"
        ])
        if !expectedLabCards.isSubset(of: releaseEvidenceLabs) {
            violations.append("runtime-evidence-lab-coverage")
        }

        for violation in NFDefaultContentCatalog.audit() {
            violations.append("runtime-default-catalog-\(violation)")
        }
        for violation in NFBundledRetrievalCatalog.audit() {
            violations.append("runtime-bundled-retrieval-\(violation)")
        }

        return violations.sorted()
    }
}

enum NFReleaseContentGate {
    private static let runtimeViolations = NFReleaseContentRuntimeBridge.audit()

    @discardableResult
    static func requireVerified() throws -> NFReleaseContentManifest {
        let manifest = try NFReleaseContentIntegrity.requireVerified()
        guard runtimeViolations.isEmpty else {
            throw NFReleaseContentIntegrityError.runtimeCatalogMismatch(runtimeViolations)
        }
        return manifest
    }
}
