import CryptoKit
import Foundation

@main
enum NFReleaseContentManifestTool {
    enum ToolError: Error {
        case usage
        case invalidPrivateKey
        case invalidPublicKey
        case invalidSignature
    }

    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else { throw ToolError.usage }
        switch command {
        case "emit-manifest":
            guard arguments.count == 2 else { throw ToolError.usage }
            let manifest = try NFReleaseContentIntegrity.makeManifest()
            try NFReleaseContentIntegrity.canonicalManifestData(manifest)
                .write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
        case "generate-key":
            guard arguments.count == 3 else { throw ToolError.usage }
            let key = P256.Signing.PrivateKey()
            try key.rawRepresentation.base64EncodedData()
                .write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
            try key.publicKey.x963Representation.base64EncodedData()
                .write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
        case "sign":
            guard arguments.count == 4 else { throw ToolError.usage }
            let manifestData = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            let privateText = try String(contentsOfFile: arguments[2], encoding: .utf8)
            guard let privateData = Data(base64Encoded: privateText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let privateKey = try? P256.Signing.PrivateKey(rawRepresentation: privateData) else {
                throw ToolError.invalidPrivateKey
            }
            let signature = try privateKey.signature(for: manifestData)
            try signature.derRepresentation.base64EncodedData()
                .write(to: URL(fileURLWithPath: arguments[3]), options: .atomic)
        case "verify":
            guard arguments.count == 4 else { throw ToolError.usage }
            let manifestData = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            let signatureText = try String(contentsOfFile: arguments[2], encoding: .utf8)
            let publicText = try String(contentsOfFile: arguments[3], encoding: .utf8)
            guard let signature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ToolError.invalidSignature
            }
            guard let publicKey = Data(base64Encoded: publicText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ToolError.invalidPublicKey
            }
            _ = try NFReleaseContentIntegrity.verify(
                manifestData: manifestData,
                signatureDER: signature,
                publicKeyX963: publicKey
            )
        default:
            throw ToolError.usage
        }
    }
}
