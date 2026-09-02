import CryptoKit
import Foundation
import XCTest

@testable import NeuroForge

final class ReleaseContentIntegrityTests: XCTestCase {
    func testReleaseInventoryMeetsEveryMinimumWithoutDuplicateIDs() throws {
        let inventory = NFReleaseContentCatalog.inventory
        XCTAssertEqual(inventory.contentVersion, "1.0.0-rc.1")
        XCTAssertEqual(Set(inventory.collections.map(\.id)), Set(NFReleaseContentCollectionID.allCases))
        XCTAssertTrue(NFReleaseContentCatalog.audit(inventory).isEmpty)

        var allIDs = Set<String>()
        for collectionID in NFReleaseContentCollectionID.allCases {
            let collection = try XCTUnwrap(inventory.collection(collectionID))
            XCTAssertGreaterThanOrEqual(collection.descriptors.count, collectionID.releaseMinimum, collectionID.rawValue)
            for descriptor in collection.descriptors {
                XCTAssertTrue(allIDs.insert(descriptor.id).inserted, descriptor.id)
                XCTAssertFalse(descriptor.title.isEmpty)
                XCTAssertFalse(descriptor.content.isEmpty)
            }
        }
    }

    func testReleaseInventoryHasRequiredInternalShapes() throws {
        let inventory = NFReleaseContentCatalog.inventory
        let mentalTemplates = try XCTUnwrap(inventory.collection(.mentalMathPackTemplates)).descriptors
        let packs = Dictionary(grouping: mentalTemplates, by: { $0.attributes["pack"] ?? "" })
        XCTAssertEqual(packs.count, 4)
        XCTAssertTrue(packs.values.allSatisfy { $0.count == 60 })
        XCTAssertTrue(packs.values.allSatisfy { Set($0.map(\.family)).count == 10 })

        let baseline = try XCTUnwrap(inventory.collection(.baselineAlternateForms)).descriptors
        let alternateGroups = Dictionary(grouping: baseline, by: { $0.attributes["alternateFormGroup"] ?? "" })
        XCTAssertEqual(alternateGroups.count, 60)
        for descriptors in alternateGroups.values {
            XCTAssertEqual(descriptors.count, 2)
            XCTAssertEqual(Set(descriptors.compactMap { $0.attributes["form"] }), Set(["a", "b"]))
        }

        let missions = try XCTUnwrap(inventory.collection(.weeklyMissionSkeletons)).descriptors
        XCTAssertEqual(missions.count, 24)
        XCTAssertEqual(Set(missions.map(\.family)).count, 6)

        let cards = try XCTUnwrap(inventory.collection(.evidenceCards)).descriptors
        XCTAssertEqual(cards.count, 10)
        XCTAssertTrue(cards.allSatisfy {
            $0.attributes["reviewStatus"] == "reviewed-release-claims-checklist-v1"
                && $0.attributes["claimScope"] == "in-app-evidence-only"
                && !($0.attributes["limitation"] ?? "").isEmpty
        })
    }

    func testCatalogSelectionAndManifestEncodingAreDeterministic() throws {
        let inventory = NFReleaseContentCatalog.inventory
        for collectionID in NFReleaseContentCollectionID.allCases {
            XCTAssertEqual(
                inventory.descriptor(collection: collectionID, seed: 0xDEAD_BEEF),
                inventory.descriptor(collection: collectionID, seed: 0xDEAD_BEEF)
            )
        }

        let first = try NFReleaseContentIntegrity.makeManifest()
        let second = try NFReleaseContentIntegrity.makeManifest()
        XCTAssertEqual(first, second)
        XCTAssertEqual(
            try NFReleaseContentIntegrity.canonicalManifestData(first),
            try NFReleaseContentIntegrity.canonicalManifestData(second)
        )
        XCTAssertEqual(first.rootDigest, "9c0136ff3da68476d59240ed4571a0754bc1cbdde290318632831fbb93c65f2d")
    }

    func testBundledManifestSignatureAndRuntimeCatalogBridgesVerify() throws {
        let manifest = try NFReleaseContentGate.requireVerified()
        XCTAssertEqual(manifest.contentVersion, NFReleaseContentCatalog.contentVersion)
        XCTAssertEqual(manifest.entries.count, NFReleaseContentCollectionID.allCases.count)
        XCTAssertTrue(NFReleaseContentRuntimeBridge.audit().isEmpty)

        let generated = try NFFallbackExerciseGenerator.generate(
            NFExerciseGenerationRequest(seed: 7, index: 0, lab: .mentalMath, purpose: .practice)
        )
        XCTAssertFalse(generated.id.isEmpty)
    }

    func testBundledManifestHasOneSignedEntryPerReleaseCollection() throws {
        let manifest = try NFReleaseContentIntegrity.requireVerified()
        let entries = Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.collectionID, $0) })
        XCTAssertEqual(entries.count, NFReleaseContentCollectionID.allCases.count)
        for collectionID in NFReleaseContentCollectionID.allCases {
            let entry = try XCTUnwrap(entries[collectionID])
            XCTAssertGreaterThanOrEqual(entry.descriptorCount, entry.minimumCount)
            XCTAssertEqual(entry.minimumCount, collectionID.releaseMinimum)
            XCTAssertEqual(entry.sha256.count, 64)
        }
    }

    func testTamperedCanonicalManifestFailsSignatureVerification() throws {
        let manifest = try NFReleaseContentIntegrity.makeManifest()
        let original = try NFReleaseContentIntegrity.canonicalManifestData(manifest)
        let originalText = try XCTUnwrap(String(data: original, encoding: .utf8))
        let tampered = Data(originalText.replacingOccurrences(of: "1.0.0-rc.1", with: "1.0.0-rc.2").utf8)
        let signature = try bundledSignatureData()
        let publicKey = try XCTUnwrap(Data(base64Encoded: NFReleaseContentIntegrity.releasePublicKeyBase64))

        XCTAssertThrowsError(try NFReleaseContentIntegrity.verify(
            manifestData: tampered,
            signatureDER: signature,
            publicKeyX963: publicKey
        )) { error in
            XCTAssertEqual(error as? NFReleaseContentIntegrityError, .invalidSignature)
        }
    }

    func testTamperedSignatureFailsClosed() throws {
        let key = P256.Signing.PrivateKey()
        let data = try NFReleaseContentIntegrity.canonicalManifestData(
            NFReleaseContentIntegrity.makeManifest()
        )
        var signature = try key.signature(for: data).derRepresentation
        signature[signature.index(before: signature.endIndex)] ^= 0x01

        XCTAssertThrowsError(try NFReleaseContentIntegrity.verify(
            manifestData: data,
            signatureDER: signature,
            publicKeyX963: key.publicKey.x963Representation
        )) { error in
            XCTAssertEqual(error as? NFReleaseContentIntegrityError, .invalidSignature)
        }
    }

    func testValidlySignedButAlteredCountCannotPassInventoryComparison() throws {
        let original = try NFReleaseContentIntegrity.makeManifest()
        var entries = original.entries
        let first = try XCTUnwrap(entries.first)
        entries[0] = NFReleaseContentManifest.Entry(
            collectionID: first.collectionID,
            descriptorCount: first.descriptorCount + 1,
            minimumCount: first.minimumCount,
            sha256: first.sha256
        )
        let altered = NFReleaseContentManifest(
            manifestSchemaVersion: original.manifestSchemaVersion,
            contentVersion: original.contentVersion,
            minimumAppBuild: original.minimumAppBuild,
            signatureAlgorithm: original.signatureAlgorithm,
            entries: entries,
            rootDigest: original.rootDigest
        )
        let key = P256.Signing.PrivateKey()
        let data = try NFReleaseContentIntegrity.canonicalManifestData(altered)
        let signature = try key.signature(for: data).derRepresentation

        XCTAssertThrowsError(try NFReleaseContentIntegrity.verify(
            manifestData: data,
            signatureDER: signature,
            publicKeyX963: key.publicKey.x963Representation
        )) { error in
            XCTAssertEqual(error as? NFReleaseContentIntegrityError, .inventoryMismatch)
        }
    }

    func testResignedInventoryBelowMinimumStillFailsStructuralAudit() throws {
        let release = NFReleaseContentCatalog.inventory
        var collections = release.collections
        let index = try XCTUnwrap(collections.firstIndex { $0.id == .weeklyMissionSkeletons })
        let original = collections[index]
        collections[index] = NFReleaseContentCollection(
            id: original.id,
            descriptors: Array(original.descriptors.dropLast())
        )
        let shortened = NFReleaseContentInventory(
            contentVersion: release.contentVersion,
            collections: collections
        )
        let manifest = try NFReleaseContentIntegrity.makeManifest(for: shortened)
        let data = try NFReleaseContentIntegrity.canonicalManifestData(manifest)
        let key = P256.Signing.PrivateKey()
        let signature = try key.signature(for: data).derRepresentation

        XCTAssertThrowsError(try NFReleaseContentIntegrity.verify(
            manifestData: data,
            signatureDER: signature,
            publicKeyX963: key.publicKey.x963Representation,
            expectedInventory: shortened
        )) { error in
            guard let integrityError = error as? NFReleaseContentIntegrityError,
                  case let .inventoryAuditFailed(violations) = integrityError else {
                return XCTFail("Expected structural audit failure, got \(error)")
            }
            XCTAssertTrue(violations.contains("minimum:weekly.mission-skeletons"))
            XCTAssertTrue(violations.contains("weekly-six-month-rotation"))
        }
    }

    func testNonCanonicalEncodingIsRejectedEvenWhenItHasAValidSignature() throws {
        let manifest = try NFReleaseContentIntegrity.makeManifest()
        let encoded = try JSONEncoder().encode(manifest)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let key = P256.Signing.PrivateKey()
        let signature = try key.signature(for: pretty).derRepresentation

        XCTAssertThrowsError(try NFReleaseContentIntegrity.verify(
            manifestData: pretty,
            signatureDER: signature,
            publicKeyX963: key.publicKey.x963Representation
        )) { error in
            XCTAssertEqual(error as? NFReleaseContentIntegrityError, .nonCanonicalManifest)
        }
    }

    private func bundledSignatureData() throws -> Data {
        let candidates = [Bundle.main, Bundle(for: ReleaseContentIntegrityTests.self)]
        let url = try XCTUnwrap(candidates.lazy.compactMap {
            $0.url(
                forResource: NFReleaseContentIntegrity.signatureResourceName,
                withExtension: "txt"
            )
        }.first)
        let text = try String(contentsOf: url, encoding: .utf8)
        return try XCTUnwrap(Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}
