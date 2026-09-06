#!/usr/bin/env python3
"""Create deterministic, synthetic JSON archives without opening a user store.

Default: regenerate the small reviewable fixture package next to this script.
--check: compare the package byte-for-byte without modifying it.
--output-dir /tmp/nf-golden --large-count 10000: also expand the large recipe.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path

STAMP = "2026-09-04T12:00:00Z"
SEED = 347811
VERSION = 18
ROOT = Path(__file__).resolve().parent


def uid(category: int, ordinal: int = 1) -> str:
    return f"{category:08x}-0000-4000-8000-{ordinal:012x}"


def encode(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def profile() -> dict:
    return dict(id=uid(0xF001), createdAt=STAMP, modifiedAt=STAMP, stage="undisclosed", fields=["general"], goals=[],
        dailyDuration=5, timingMode="untimed", aiMode="disabled", iCloudEnabled=False, reducedMotion=True,
        hideTimers=True, excludeVisualSpatial=False, onboardingVersion=1, claimsPolicyAcknowledgedVersion=1,
        pccConsentVersion=0, pccConsentAt=None, preferredLanguageCode="en", trainingDays=["1", "2", "3", "4", "5", "6", "7"],
        dayBoundaryHour=4, ageBandAcknowledged16Plus=True, preferredAnswerMode="keyboard",
        reinforcementHapticsEnabled=False, reinforcementSoundEnabled=False)


def envelope() -> dict:
    return dict(archiveVersion=VERSION, exportedAt=STAMP, appVersion="synthetic-golden-v1", profile=profile(),
        attempts=[], attemptReflections=[], documents=[], sourceChunks=[], aiGenerations=[], sessionCheckpoints=[],
        dailyPlans=[], inputCalibrations=[], progressAnnotations=[], excludedPrivateAnnotationCount=0,
        weeklyTransferState=None, reassessmentState=None, adaptivePlanHistory=[], quarantinedReports=[])


def attempt(ordinal: int = 1) -> dict:
    return dict(id=uid(0xA110, ordinal), sessionID=uid(0xA120, ordinal), itemID=f"golden.numeric.{ordinal:05d}",
        templateID="nf.fallback.mentalMath.practice.v3.rapid-recall", seed=SEED, lab="mentalMath", skillID="skill.mentalMath",
        skillWeights={"skill.mentalMath": 1}, domainContext="general", transferBrief=None, spatialDifficultyParameters=None,
        prompt="Synthetic golden question: what is 6 × 4?", response=' { "numeric" : { "_0" : { "value" : "24", "unit" : null } } } ',
        correctAnswer="24", isCorrect=True, confidence="certain", shownAt=STAMP, submittedAt=STAMP, activeDurationSeconds=12,
        evidenceClass="practice", sessionSource="focused", evidenceWeight=1, errorCode=None, scoringVersion=7,
        deviceID=uid(0xD001), generationID=None, sourceDocumentIDs=[], sourceChunkIDs=[], responseFormat="numeric", wasSkipped=False,
        validationVersion=1, assessmentBlock=None, planID=None, planBlockID=None, deterministicCredit=1, hintCount=0,
        inputMode="keyboard", interruptionCount=0, revisionCount=0, accommodationFlags=[], wasTimed=False,
        assessmentDescriptorID=None, assessmentTemplateFamily=None, assessmentFormat=None, assessmentMechanicID=None,
        assessmentSubskillID=None, assessmentSeed=None, assessmentCycle=None)


def science() -> dict:
    row = attempt(2)
    row.update(itemID="golden.disputed-science", templateID="nf.fallback.scientificReasoning.practice.v3.data-forensics.uncertainty",
        lab="scientificReasoning", skillID="skill.scientificReasoning", skillWeights={"skill.scientificReasoning": 1},
        prompt="A synthetic report gives group A mean 22 and group B mean 31, with overlapping uncertainty intervals. Which conclusion is supported?",
        response=' { "singleChoice" : { "optionID" : "correct" } } ',
        correctAnswer="Group B has the higher observed mean; uncertainty limits the conclusion.", responseFormat="singleChoice")
    return row


def self_check() -> dict:
    row = attempt(3)
    row.update(itemID="golden.external-self-check", templateID="synthetic.external.self-check.v1", lab="retrieval",
        skillID="skill.retrieval", skillWeights={"skill.retrieval": 1}, evidenceClass="documentPractice", responseFormat="sourceSelfCheck",
        prompt="Synthetic external self-check: recall the source relationship.",
        response=' { "selfCheck" : { "_0" : { "rating" : "matched", "reflection" : "Synthetic recall only.\\n日本語の記録" } } } ',
        correctAnswer="Synthetic reference relationship", sourceDocumentIDs=[uid(0xDE1E7ED)], sourceChunkIDs=["deleted.synthetic.chunk"])
    return row


def library() -> dict:
    archive = envelope()
    archive["attempts"] = [self_check()]
    text = "Synthetic source note alpha. No personal data.\nSecond line."
    digest = hashlib.sha256(text.encode()).hexdigest()
    for ordinal in (1, 2):
        document_id = uid(0xD0C0, ordinal)
        archive["documents"].append(dict(id=document_id, filename=f"synthetic-note-{ordinal}.txt", typeIdentifier="public.plain-text",
            sizeBytes=len(text.encode()), importedAt=STAMP, indexState="indexed", aiPolicy="onDeviceOnly", syncPolicy="localOnly",
            pccExcerptConsentPolicyVersion=0, pccExcerptConsentDocumentID="", pccExcerptConsentedAt=None,
            characterCount=len(text), chunkCount=1, extractionVersion=1, csvSelectedColumnIDs=[], indexError=None))
        archive["sourceChunks"].append(dict(id=f"synthetic.chunk.{ordinal}", documentID=document_id, documentVersion=1,
            sourceName=f"synthetic-note-{ordinal}.txt", page=None, lineStart=1, lineEnd=2, section=None, text=text,
            contentHash=digest, ordinal=0, characterStart=0, characterEnd=len(text), nearbyHeading=None, language="en", contentTypeTags=["prose"]))
    return archive


def small_files() -> dict[str, bytes]:
    archives: dict[str, object] = {"fresh-v18.json": envelope()}
    legacy = envelope()
    legacy["attempts"] = [attempt(), science(), self_check()]
    for version in range(14, 19):
        archive = copy.deepcopy(legacy)
        archive["archiveVersion"] = version
        if version < 15:
            archive.pop("attemptReflections")
        if version < 16:
            archive.pop("adaptivePlanHistory")
        archives[f"legacy-v{version}.json"] = archive
    disputed = envelope()
    disputed["attempts"] = [science()]
    archives["disputed-science-v18.json"] = disputed
    external = envelope()
    external["attempts"] = [self_check()]
    archives["external-self-check-v18.json"] = external
    archives["source-duplicates-deleted-reference-v18.json"] = library()
    orphan = library()
    orphan["sourceChunks"][0]["documentID"] = uid(0xDE1E7ED)
    archives["invalid-source-reference-v18.json"] = orphan
    duplicate = envelope()
    duplicate["attempts"] = [attempt(), attempt()]
    archives["invalid-duplicate-attempt-v18.json"] = duplicate
    future = envelope()
    future["archiveVersion"] = 99
    archives["future-v99.json"] = future
    archives["history-10000.recipe.json"] = dict(recipeVersion=1, kind="synthetic-history", count=10000,
        creator="regenerate.py --output-dir /tmp/neuroforge-golden --large-count 10000", fixedSeed=SEED,
        fixedTimestamp=STAMP, attemptUUIDCategory="0000a110", sessionUUIDCategory="0000a120",
        rawResponse=attempt()["response"], expandedJSONCommitted=False)
    archives["runtime-phases.recipe.json"] = dict(recipeVersion=1, creator="DataExportRoundTripTests.testGoldenRuntimeCapturesPreserveThreePhasesAndInterruptedTiming",
        fixedSeed=SEED, fixedOwnerID=uid(0xD001), fixedMonotonicStart=100, interruptedAt=112,
        fixedSessionUUIDCategory="0000a120", phases=["item", "feedback", "selfCheckComparison", "interruptedTimedItem"],
        createsThrough="NFUniversalSessionRuntime public methods and NFDataExportService.makeExports",
        mutatesProduction=False, committedHistoricalSnapshot=False,
        note="Runtime-owned slot/attempt IDs and wall-clock capture timestamps are generated by the production runtime; tests compare their exact captured values after restore, not fabricated fixed replacements.")
    files = {name: encode(value) for name, value in archives.items()}
    files["malformed-truncated.json"] = b'{"archiveVersion":18,"attempts":['
    entries = []
    for name, data in sorted(files.items()):
        obj = archives.get(name, {})
        entries.append(dict(path=name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
            expectedAttemptCount=len(obj.get("attempts", [])) if isinstance(obj, dict) and "archiveVersion" in obj else None,
            expectedDocumentCount=len(obj.get("documents", [])) if isinstance(obj, dict) and "archiveVersion" in obj else None,
            expectedChunkCount=len(obj.get("sourceChunks", [])) if isinstance(obj, dict) and "archiveVersion" in obj else None,
            acceptedByRestore=not name.startswith(("invalid-", "future-", "malformed-", "history-", "runtime-"))))
    files["manifest.json"] = encode(dict(fixturePackageVersion=1, provenance="synthetic-created-from-declared-archive-schema",
        creator="regenerate.py", fixedTimestamp=STAMP, fixedSeed=SEED, containsRealUserData=False,
        shippedStoreSnapshot=False, entries=entries,
        invariants=["versions14–18 use the actual decoder and restore service", "exact original raw response string preserved",
            "legacy science without its original table is unverifiable, not counterfactually graded",
            "external self-check remains personal-study history", "duplicate source content does not erase distinct identities",
            "deleted references in retained historical answers remain authentic", "malformed/future/reference-invalid data cannot mutate destination",
            "large history expands deterministically on demand"],
        gaps=["No historical binary SwiftData/CloudKit store is claimed.", "No physical-device, VoiceOver, Pencil, performance percentile, or learning-effect claim.",
            "Exact runtime phases are constructed through public runtime APIs in tests, never manufactured as old committed JSON.",
            "The disputed science row intentionally has no original table; exact invalid interval geometry has independent policy tests."]))
    return files


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--large-count", type=int, default=0)
    args = parser.parse_args()
    if not 0 <= args.large_count <= 10000:
        parser.error("large-count must be between 0 and 10000")
    if args.large_count and args.output_dir.resolve() == ROOT:
        parser.error("expanded history requires a separate --output-dir; do not commit it")
    files = small_files()
    if args.large_count:
        archive = envelope()
        archive["attempts"] = [attempt(index + 1) for index in range(args.large_count)]
        files[f"history-{args.large_count}-v18.json"] = encode(archive)
    if args.check:
        wrong = [name for name, data in files.items() if not (args.output_dir / name).is_file() or (args.output_dir / name).read_bytes() != data]
        if wrong:
            raise SystemExit("Fixture mismatch: " + ", ".join(wrong))
        print(f"Verified {len(files)} deterministic synthetic fixture files")
    else:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        for name, data in files.items():
            (args.output_dir / name).write_bytes(data)
        print(f"Wrote {len(files)} deterministic synthetic fixture files to {args.output_dir}")


if __name__ == "__main__":
    main()
