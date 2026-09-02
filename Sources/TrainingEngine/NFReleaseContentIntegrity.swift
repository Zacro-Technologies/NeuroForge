import CryptoKit
import Foundation

struct NFReleaseContentManifest: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let collectionID: NFReleaseContentCollectionID
        let descriptorCount: Int
        let minimumCount: Int
        let sha256: String
    }

    let manifestSchemaVersion: Int
    let contentVersion: String
    let minimumAppBuild: Int
    let signatureAlgorithm: String
    let entries: [Entry]
    let rootDigest: String
}

enum NFReleaseContentIntegrityError: Error, Equatable, Sendable {
    case missingResource(String)
    case unreadableResource(String)
    case malformedManifest
    case nonCanonicalManifest
    case malformedSignature
    case invalidSignature
    case unsupportedSignatureAlgorithm
    case incompatibleManifestVersion
    case incompatibleContentVersion
    case incompatibleAppBuild
    case inventoryAuditFailed([String])
    case inventoryMismatch
    case runtimeCatalogMismatch([String])
}

enum NFReleaseContentIntegrity {
    static let manifestResourceName = "NeuroForgeReleaseContentManifest"
    static let signatureResourceName = "NeuroForgeReleaseContentManifest.signature"
    static let signatureAlgorithm = "ECDSA-P256-SHA256-DER"
    static let minimumAppBuild = 1

    /// ANSI X9.63 representation of the offline release-signing public key.
    /// The corresponding private key is intentionally not present in this
    /// repository or app bundle.
    static let releasePublicKeyBase64 = "BKHaww7UXgVfAomPGKLHrxX7HOT2kcduq9+W8LsTYnOLHAfP7hhYMahIAukD56wwixI0JlAfxCdIjvyhLX0dkmE="

    private struct VerificationSnapshot: Sendable {
        let manifest: NFReleaseContentManifest?
        let error: NFReleaseContentIntegrityError?
    }

    private static let bundledSnapshot: VerificationSnapshot = {
        do {
            return VerificationSnapshot(manifest: try verifyBundled(), error: nil)
        } catch let error as NFReleaseContentIntegrityError {
            return VerificationSnapshot(manifest: nil, error: error)
        } catch {
            return VerificationSnapshot(manifest: nil, error: .malformedManifest)
        }
    }()

    @discardableResult
    static func requireVerified() throws -> NFReleaseContentManifest {
        if let error = bundledSnapshot.error { throw error }
        guard let manifest = bundledSnapshot.manifest else {
            throw NFReleaseContentIntegrityError.malformedManifest
        }
        return manifest
    }

    static func makeManifest(
        for inventory: NFReleaseContentInventory = NFReleaseContentCatalog.inventory,
        minimumAppBuild: Int = minimumAppBuild
    ) throws -> NFReleaseContentManifest {
        let entries = try inventory.collections
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .map { collection in
                NFReleaseContentManifest.Entry(
                    collectionID: collection.id,
                    descriptorCount: collection.descriptors.count,
                    minimumCount: collection.id.releaseMinimum,
                    sha256: sha256(try canonicalCollectionData(collection))
                )
            }
        return NFReleaseContentManifest(
            manifestSchemaVersion: NFReleaseContentCatalog.schemaVersion,
            contentVersion: inventory.contentVersion,
            minimumAppBuild: minimumAppBuild,
            signatureAlgorithm: signatureAlgorithm,
            entries: entries,
            rootDigest: sha256(try canonicalJSONData(entries))
        )
    }

    static func canonicalManifestData(_ manifest: NFReleaseContentManifest) throws -> Data {
        try canonicalJSONData(manifest)
    }

    static func verify(
        manifestData: Data,
        signatureDER: Data,
        publicKeyX963: Data,
        expectedInventory: NFReleaseContentInventory = NFReleaseContentCatalog.inventory,
        currentAppBuild: Int = minimumAppBuild
    ) throws -> NFReleaseContentManifest {
        let normalizedData = trimmedASCIIWhitespace(manifestData)
        let manifest: NFReleaseContentManifest
        do {
            manifest = try JSONDecoder().decode(NFReleaseContentManifest.self, from: normalizedData)
        } catch {
            throw NFReleaseContentIntegrityError.malformedManifest
        }

        guard (try? canonicalManifestData(manifest)) == normalizedData else {
            throw NFReleaseContentIntegrityError.nonCanonicalManifest
        }
        guard manifest.signatureAlgorithm == signatureAlgorithm else {
            throw NFReleaseContentIntegrityError.unsupportedSignatureAlgorithm
        }

        let publicKey: P256.Signing.PublicKey
        let signature: P256.Signing.ECDSASignature
        do {
            publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyX963)
            signature = try P256.Signing.ECDSASignature(derRepresentation: signatureDER)
        } catch {
            throw NFReleaseContentIntegrityError.malformedSignature
        }
        guard publicKey.isValidSignature(signature, for: normalizedData) else {
            throw NFReleaseContentIntegrityError.invalidSignature
        }

        guard manifest.manifestSchemaVersion == NFReleaseContentCatalog.schemaVersion else {
            throw NFReleaseContentIntegrityError.incompatibleManifestVersion
        }
        guard manifest.contentVersion == NFReleaseContentCatalog.contentVersion,
              expectedInventory.contentVersion == NFReleaseContentCatalog.contentVersion else {
            throw NFReleaseContentIntegrityError.incompatibleContentVersion
        }
        guard manifest.minimumAppBuild <= currentAppBuild else {
            throw NFReleaseContentIntegrityError.incompatibleAppBuild
        }

        let violations = NFReleaseContentCatalog.audit(expectedInventory)
        guard violations.isEmpty else {
            throw NFReleaseContentIntegrityError.inventoryAuditFailed(violations)
        }
        let expected = try makeManifest(
            for: expectedInventory,
            minimumAppBuild: manifest.minimumAppBuild
        )
        guard manifest == expected else {
            throw NFReleaseContentIntegrityError.inventoryMismatch
        }
        return manifest
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func verifyBundled() throws -> NFReleaseContentManifest {
        let bundles = [Bundle.main, Bundle(for: NFReleaseContentBundleAnchor.self)]
        guard let manifestURL = bundles.lazy.compactMap({
            $0.url(forResource: manifestResourceName, withExtension: "json")
        }).first else {
            throw NFReleaseContentIntegrityError.missingResource("\(manifestResourceName).json")
        }
        guard let signatureURL = bundles.lazy.compactMap({
            $0.url(forResource: signatureResourceName, withExtension: "txt")
        }).first else {
            throw NFReleaseContentIntegrityError.missingResource("\(signatureResourceName).txt")
        }

        let manifestData: Data
        let signatureText: String
        do {
            manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
            signatureText = try String(contentsOf: signatureURL, encoding: .utf8)
        } catch {
            throw NFReleaseContentIntegrityError.unreadableResource(manifestURL.lastPathComponent)
        }
        guard let signatureData = Data(
            base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)
        ), let publicKey = Data(base64Encoded: releasePublicKeyBase64) else {
            throw NFReleaseContentIntegrityError.malformedSignature
        }
        return try verify(
            manifestData: manifestData,
            signatureDER: signatureData,
            publicKeyX963: publicKey
        )
    }

    private static func canonicalCollectionData(_ collection: NFReleaseContentCollection) throws -> Data {
        let normalized = NFReleaseContentCollection(
            id: collection.id,
            descriptors: collection.descriptors.sorted { $0.id < $1.id }
        )
        return try canonicalJSONData(normalized)
    }

    private static func canonicalJSONData<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func trimmedASCIIWhitespace(_ data: Data) -> Data {
        let whitespace: Set<UInt8> = [0x09, 0x0A, 0x0D, 0x20]
        guard let first = data.firstIndex(where: { !whitespace.contains($0) }),
              let last = data.lastIndex(where: { !whitespace.contains($0) }) else {
            return Data()
        }
        return Data(data[first...last])
    }
}

private final class NFReleaseContentBundleAnchor {}
