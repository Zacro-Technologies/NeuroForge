# Release content signing

NeuroForge treats the Swift release inventory as the canonical content source. `NFReleaseContentManifestTool` emits a canonical JSON manifest containing every collection count and SHA-256 digest, signs that exact byte sequence with P-256 ECDSA, and verifies it against an offline public key. Runtime generation remains unavailable if the signature, version, inventory, or concrete runtime-bank bridge fails.

## Release procedure

1. Bump `NFReleaseContentCatalog.contentVersion` whenever a signed descriptor, minimum, or runtime content identity changes.
2. Run the generator/property/localization/accessibility checks and complete the independent answer and construct review required by the release plan.
3. Compile the offline helper from the repository root:

   ```sh
   xcrun swiftc -O \
     Sources/TrainingEngine/NFReleaseContentCatalog.swift \
     Sources/TrainingEngine/NFReleaseContentIntegrity.swift \
     Tools/NFReleaseContentManifestTool.swift \
     -o /tmp/NFReleaseContentManifestTool
   ```

4. In the approved release-signing environment, emit the canonical manifest and sign it with the protected release key:

   ```sh
   /tmp/NFReleaseContentManifestTool emit-manifest /tmp/NeuroForgeReleaseContentManifest.json
   /tmp/NFReleaseContentManifestTool sign \
     /tmp/NeuroForgeReleaseContentManifest.json \
     /secure/offline/location/neuroforge-content-private-key \
     /tmp/NeuroForgeReleaseContentManifest.signature.txt
   /tmp/NFReleaseContentManifestTool verify \
     /tmp/NeuroForgeReleaseContentManifest.json \
     /tmp/NeuroForgeReleaseContentManifest.signature.txt \
     /secure/offline/location/neuroforge-content-public-key
   ```

5. Copy only the manifest and signature into `Sources/Resources`, and update `releasePublicKeyBase64` only when the release key is intentionally rotated.
6. Regenerate the project and run `ReleaseContentIntegrityTests` plus the complete application suite before producing signed archives.

The private key must never be placed in this repository, an app bundle, an xcresult bundle, ordinary CI artifacts, or developer logs. `generate-key` exists for controlled key ceremonies and local tamper-test fixtures; production key custody and rotation belong to the release-signing system. A valid signature proves payload identity, not subject-matter correctness, so it does not replace independent content review.
