# NeuroForge

NeuroForge is an AI-centered STEM learning app for iPhone, iPad, and Mac. AI tutoring, short-response grading, source-based study, question generation and personalized coaching are central to the intended experience. Local processing keeps useful practice and saved work available offline; it is not a privacy-led restriction on model use.

The [revised product direction](Documentation/AI_Product_Direction_2026-09-05.md) and [improvement specification v1.1](Documentation/Improvement_Spec_2026-09-04/README.md) define the current target. They supersede earlier deterministic-only grading, optional-AI, Shortcut-only and privacy-first product restrictions. Exact evaluators remain useful for arithmetic and formal tasks; validated AI rubric evaluators are required for short answers, explanations and other semantic responses. Capable local and cloud models can contribute to grading, tutoring, generated practice and adaptive recommendations.

**Implementation status:** this documentation revision does not add those capabilities to the application. The implementation inventory below records existing code, including its older deterministic scoring and Shortcut authoring limits. Those limits are migration work, not the desired product premise. The [implementation ledger](Documentation/Improvement_Implementation_2026-09-04/README.md) records previous work and must be reassessed against the revised specification.

## Current implementation inventory

### Reasoning and session engine

- Seven complete training labs: Mental Mathematics, Spatial Reasoning, Quantitative Intuition, Scientific Reasoning, Logic & Debugging, Retrieval Practice, and Transfer Lab.
- A searchable offline practice catalog ships 7,000 canonical questions—1,000 per lab—across all 58 deterministic exercise families, with eight selectable STEM field perspectives. Mixed focused quizzes reserve the versioned 1,000-question lab bank at launch and exhaust it without replacement, so abandoned quizzes still advance. Selected-activity launches also advance immediately, produce a different full sequence, and exclude normalized task/stimulus/answer duplicates inside the run; an individual activity family is not claimed to contain 1,000 questions, and UUID or option-order changes never count as novelty. Retrieval Practice contributes 1,000 canonical question contracts: 200 editorial concept targets plus 800 computed instances across 80 deterministic calculation families, balanced at 125 contracts in each STEM field. Mechanic-bounded puzzles retain authoritative scoring and narrow evidence claims. See [Default content catalog](Documentation/DefaultContentCatalog.md).
- Deterministic exercise inventories for practice, near transfer, applied transfer, retention, baseline, protected holdouts, and personal document practice. Seeds, template families, versions, content digests, provenance, and answer keys are durable and reproducible.
- Eight response schemas: numeric entry, single choice, multiple choice, ordered steps, short text, explicit self-check, claim/evidence matching, and logic-state tracing.
- Authoritative scoring with unit and tolerance handling, deterministic partial credit, a bounded typed pseudocode interpreter for debugging traces, structured error codes, protected assessment feedback timing, and accessibility metadata.
- A versioned release inventory covers all specified content minima across 14 auditable collections. A canonical manifest records every collection count and SHA-256 digest, is signed offline with P-256 ECDSA, and is verified—together with concrete runtime-bank bridges—before any fallback exercise can be generated. Tampering, truncation, version drift, and runtime/catalog disagreement fail closed; the private signing key is not part of the repository or app bundle.
- Native RealityKit scenes cover the 3D spatial families, with a user-selectable static 2D fallback, reduced-motion-safe orbit behavior, deterministic scene identity, and equivalent accessibility descriptions for coordinates, vectors, projections, cutting planes, cross-sections, and cube nets.
- Mental-math authority uses exact rational/decimal arithmetic rather than floating-point equality. Its progression is explicitly accuracy → flexibility → automaticity → transfer, keeps first exposure untimed, captures estimate-before-exact and unit evidence independently, supports score-preserving calculation-chain replay, validates all 11 free cube nets algorithmically, and ships four deterministic 60-descriptor STEM field packs.
- Logic/debugging exercises execute only a bounded typed abstract syntax tree. A pure renderer can present that same authoritative program in neutral pseudocode, Python-like, JavaScript-like, or Swift-like syntax without parsing or executing the displayed text, so changing the language skin cannot change the trace or answer.
- Scientific figure-forensics items expose the deterministic raw observations behind their chart or summary, and spatial attempts persist both the complete difficulty vector and stimulus category so progress cannot infer mastery from one visual family.
- A shared session runtime across every lab and interaction type with confidence-before-feedback, hints where permitted, timed or untimed operation, hideable timers, no-score skips, pause/resume, text and PencilKit scratchpads, local quarantine/reporting with full provenance, summaries, durable checkpoints, stable attempt identity, and queued retry when a local write fails. Today begins with an explicit session scope, can run selected blocks continuously without rewriting the canonical plan, and can stop cleanly at any block boundary.
- High-confidence mistakes, repeated deterministic error codes, strategy mismatches, and weekly transfer attempts can trigger reflection before feedback. Learner corrections are stored as supplemental records against immutable attempts: they can improve the displayed error interpretation but can never rewrite the original response, answer key, score, credit, or evidence.

### Question sets

The Question Sets creator lets a learner shape practice by:

- reasoning lab;
- STEM field, specific topic, course, technique, or problem area;
- learning objective and difficulty;
- selected study material; and
- question form: multiple choice, short answer, numerical problem, proof/derivation, debugging, experimental design, data interpretation, or spatial transformation.

The existing implementation lets topic-only sets use the user-installed, user-configured Question Writer Shortcut. The learner chooses its **Use Model** provider; NeuroForge recommends ChatGPT but cannot attest the provider or model version. Imported sources default to **Offline only** and must be explicitly changed to **Question Writer + offline** before any excerpt is eligible. A source-backed run then identifies the selected sources and excerpt limits before asking for a second, per-run consent, and sends at most four excerpts, no more than 1,600 characters each or 4,800 characters total. Consent is bound internally to the one-run request ID and each excerpt's exact chunk identity, document version, and content hash; the expiring mailbox and source-link validator retain the exact bounded snapshots that were shown to the model. Original files, discarded excerpt tails, unselected text, answers, and progress history remain local. Returned sets pass local structure, topic-relevance, answer-leak, repetition, math-format, and source-link checks, then use recall → reveal → self-rate practice. The existing route uses reference/self-rating rather than AI rubric grading; the revised product requires a real AI grading route. The existing adaptive-population gate ties native-provider admission to the offline inventory floors; the revised specification removes that dependency for new AI capabilities. The shipping target contains no native PCC provider or managed-PCC entitlement.

Offline authoring remains available across all eight question forms. It is a first-class question-bank route, not a model fallback disguised as generated content: every form becomes an immutable typed exercise with a machine-checkable response schema and deterministic scorer. The current Shortcut route and learner self-rating do not produce AI grades; implementing validated semantic grading is required by the revised specification. For selected sources, the offline route supports complete-prose recall, while Question Writer can use bounded text extracted locally from every supported import format for open-response practice. Both routes fail closed instead of inventing filler.

Validated authored payloads use a bounded one-hour in-memory LRU and an expiring, size-limited local recovery cache. Cache identity includes source hashes, locale, prompt/schema versions, route policy, and request semantics, so stale or cross-request content is rejected instead of rebound silently.

Current background preparation creates tomorrow’s deterministic plan and maintains disposable local caches. It does not yet implement the revised AI planning, tutoring or evaluation requirements. Existing committed plans and results must survive that migration unchanged.

Authoring begins with visible progress and can be cancelled without saving a partial result. Validated sets retain their route, prompt/validator versions, citations, and a local report action. Reporting a question excludes that exact content identity from future practice and preserves a bounded diagnostic record after the disposable generation payload expires.

### Assessment, planning, and evidence

- Four resumable baseline blocks, each capped below eight minutes, cover eight independently persisted dimensions: mental arithmetic, quantitative estimation, probability, spatial transformation, data interpretation, experimental design, logic, and confidence calibration. Every dimension has at least eight protected items across at least two response formats.
- Baseline results reduce only baseline/holdout evidence and present each dimension independently with its evidence count, uncertainty band, information/exposure state, and insufficient-evidence state. Later practice cannot rewrite the baseline view, confidence calibration cannot alter another dimension, and no composite intelligence-like score exists.
- A durable unscored practice item precedes each baseline block. Reassessment uses protected alternate forms for one previously assessed block, becomes due after 28 distinct active days, remains non-blocking, lasts 4–6 minutes, and can be deferred exactly seven days without changing progress or consistency history.
- Response-adaptive item selection that updates ability and uncertainty, balances content and formats, protects holdout exposure, resumes from durable descriptor paths, and stops on target information, active-time limit, or item cap.
- Every assessment descriptor maps to a concrete generator mechanic and response format; skipped items persist as zero evidence and replay without changing ability, while quarantined descriptors are removed from future adaptive pools.
- A canonical, deterministic daily plan built from goals, skill estimates, review urgency, uncertainty, transfer gaps, recent load, accessibility, readiness, and duration constraints. Low-readiness plans reduce the selected budget without falsifying completion or performance history.
- The learner selects and persists a 12 AM–12 PM training-day boundary. Canonical plans retain timezone, UTC offset, boundary start, and next-boundary metadata; travel within 18 hours preserves the current plan and deterministically caps its recalculated boundary instead of creating a duplicate obligation.
- Multi-block Today sessions for retention review, target practice, unseen transfer, and confidence reflection, with explicit prescription reasons, offline-ready fallbacks, completion tracking, and one reasoned duration-preserving block replacement per day.
- Retention scheduling and durable weekly cross-lab transfer missions use real priority/transfer-gap inputs, exact selected-skill weights, explicit transfer dimensions, deterministic mission families and seeds, and one-day deferral without a streak penalty.
- Progress views keep practice, near transfer, applied transfer, delayed retention, protected assessment, and personal document work separate. Week/module/input/timing/domain filters remain active through skill drill-down. Accuracy uses earned deterministic credit and is shown with evidence counts, uncertainty, and confidence calibration; speed is reported only from sufficient correct, uninterrupted, actually timed evidence using a median and robust band, and is explicitly unavailable for untimed or sparse evidence. Improvement cards require separated windows, alternate forms, a positive uncertainty margin, and no detected timing/accommodation confound; otherwise the UI says evidence is insufficient or uncertain.
- Mental-math progress exposes seven independent channels—accuracy, retrieval fluency, strategy flexibility, estimation error, unit handling, retention, and transfer—with their own units and adequate-data thresholds; it never collapses them into a composite score.
- Deterministic insight rules surface strengths, current priorities, repeated scorer errors, overconfidence hotspots, and review-due families with inspectable rule IDs and attempt counts. Consistency distinguishes active days, planned rest, neutral misses, and one flexible protected pause per calendar week; rest never resets history. Optional private date-range annotations never affect scores or plans and default to exclusion from exports.

The current implementation excludes personal document practice from those standardized estimates and progress claims. The revised EVD-010 requirement adds useful AI-graded source/objective progress, review and coaching; standardized comparison still requires its own validated scope.

### Study-material grounding

- App-managed local imports for PDFs; images; plain, Markdown, HTML, and RTF text; LaTeX; CSV/TSV; JSON/JSONL/YAML/XML/TOML; Jupyter notebooks; and common source-code formats. Regular-file, supported-extension, and 50 MB gates run before copying. Imported code and structured data are read as text and never executed.
- Multi-file import runs as cancellable copy, extraction/chunking, and local-save stages off the main actor, exposes per-file progress, retains a durable extraction-failure state, and supports retry from both the batch and document detail without losing an app-managed original.
- Full-document PDFKit/text extraction and format-aware deterministic parsers preserve Markdown heading hierarchy and fenced-code language, passive HTML/RTF text, LaTeX sections and equation boundaries, source-language and symbol boundaries, quoted CSV/TSV rows, and notebook cell source while dropping notebook outputs, attachments, and metadata. Chunks carry stable content hashes, exact character offsets, page/line/section locators, nearby headings, language, and content-type tags.
- CSV document detail provides a typed schema preview, numeric/text summaries, stable column identities, and selectable-column projection. Applying a selection transactionally rebuilds the derived local chunks while preserving the original app-managed file.
- On-device Vision OCR runs automatically for imported images and only by explicit action for scanned PDFs, with warnings to verify equations and symbols against the source.
- Local retrieval over indexed chunks, stable citation IDs, deterministic source-bound question authoring, and stored generation provenance.
- Local Library search, review-aware document deletion, original-file export, and optional privacy-controlled Core Spotlight indexing.
- Originals remain local unless both the app-level preference and that document’s explicit private-original control are enabled. The private custom-zone adapter uses SHA-256 content identities, one deduplicated `CKAsset` per hash, allowlisted link metadata, durable deletion tombstones, and visible queued/uploaded/paused/error state. Extracted text, local paths, index diagnostics, and generated caches are excluded from its CloudKit schema.

### Privacy and platform integrations

- SwiftData persistence is split into disjoint durable and device-local configurations. Imported-document paths/index state, extracted chunks, input calibration, and disposable AI payloads always remain in the local-only store. The durable configuration requests a private CloudKit database only when an explicit pre-launch user preference, configured container, and signed capability evidence all agree; the local-only configuration can never receive CloudKit. The release schema is explicitly versioned and opens through a migration plan; a failed open enters a write-blocked recovery interface and rotates one protected raw-store package instead of silently resetting data.
- The privacy dashboard reports local app data, structured private-iCloud records, explicitly opted-in original document assets, and the user-configured Question Writer Shortcut separately. Question Writer consent identifies the selected sources and bounded excerpt limits for each source-backed run; it never represents the selected provider as attested. Structured SwiftData framework events and the custom original-asset queue keep separate status, timestamps, and pending counts. Sensitive durable content fields opt into CloudKit field encryption, while identity/query fields remain usable and all device-local models remain outside the cloud schema.
- Onboarding is a short three-step setup for learning focus, daily duration, and timing preference; it does not request age information. Input preferences can be changed later without blocking setup, while resetting and restarting onboarding changes preferences without deleting training history. Optional haptic and sound reinforcement are off by default, system-gated, and never required for scoring or completion.
- The export share sheet creates a versioned full JSON archive, evidence-weighted progress CSV, generated-question JSON, and detailed document/AI review-history CSV. An independent round-trip validator decodes the full archive and verifies the count and stable identity of every exported record category; this is an export-integrity harness, not a hidden restore/merge path. Recovery-oriented pending writes, transactional document deletion, and an awaited delete-all coordinator cover local records, managed files, diagnostic reports, prepared exports, AI cache, private-sync queue, reminders, Spotlight entries, and widget snapshots. Synced-document deletion persists a resumable CloudKit tombstone before removing the local copy. “Delete local data” disables the next-launch sync bootstrap and explicitly retains rather than misrepresents remote copies; when structured CloudKit is active, the app requires a reopen before local-only deletion so a SwiftData delete cannot propagate unintentionally. A cleanup failure identifies the unfinished component and remains safely retryable; success is not shown early. Skips remain present in archive/history counts but never dilute earned-credit percentages.
- Privacy manifests for the app and widget extension. The repository contains no advertising, tracking, analytics, developer-hosted service, or third-party model API integration.
- Explicit opt-in local notifications with training-day schedules, due-review reminders, weekly summaries, and quiet hours.
- Best-effort background plan preparation, source indexing, cache maintenance, and sync-assistance planning; foreground behavior remains authoritative.
- App Intents/App Shortcuts, keyboard commands, `neuroforge://` deep links, and privacy-controlled Core Spotlight search.
- A WidgetKit extension with small and medium Home Screen widgets plus circular, inline, and rectangular Lock Screen families. It reads a minimal App Group snapshot and deep-links to Today.
- Adaptive iPhone navigation and iPad/Mac split navigation, VoiceOver labels, keyboard-only paths, reduced-motion/timer controls, and visual-spatial accessibility exclusions.
- Every lab links directly to its offline methodology entry. The searchable Settings library gives purpose, method, limits, and retained-evidence cards for all seven labs.
- Dynamic model, status, field, lab, scheduler, and validator copy resolves through the saved in-app English/Japanese locale as well as SwiftUI’s locale environment. Fixed AI answer-authority prompts use the request locale for both generation instructions and independent validation.

## Architecture

```text
Sources/
  Adaptive/        Evidence reduction and deterministic legacy plan helpers
  AI/              Shortcut authoring, deterministic question sets, source grounding, OCR
  App/             Application entry point, navigation, commands, deep links
  Assessment/      Adaptive baseline, daily scheduler, retention and transfer
  DesignSystem/    Theme and reusable SwiftUI components
  Domain/          Product enums, snapshots, attempt and evidence types
  Features/        Onboarding, Today, Train, AI Studio, Progress, Library, Settings
  Integrations/    App Intents, widgets, notifications, Spotlight, background, sync policy
  Persistence/     Versioned SwiftData schema, migrations, recovery, transactions, checkpoints
  Privacy/         Versioned archive, progress, generated-question, and review-history export
  Resources/       Info, entitlements, privacy/string catalogs, signed content manifest
  TrainingEngine/  Exercise schemas, generation, validation, deterministic scoring
Widgets/           WidgetKit extension and its resources
Tests/             Exercise, AI/source, assessment/scheduler, adaptive, and system tests
project.yml        XcodeGen source of truth
```

The app targets iOS/iPadOS 26.4+ and macOS 26.4+. It uses Swift 6 strict concurrency and treats warnings as errors. `NeuroForge.xcodeproj` is generated output; make target or build-setting changes in `project.yml`.

## Generate, build, and test

Install Xcode with the required platform SDKs and [XcodeGen](https://github.com/yonaskolb/XcodeGen), then run from the repository root:

```sh
xcodegen generate

plutil -lint \
  Sources/Resources/Info.plist \
  Sources/Resources/PrivacyInfo.xcprivacy \
  Sources/Resources/NeuroForgeTestFlight.entitlements \
  Sources/Resources/NeuroForgeMac.entitlements \
  Widgets/Info.plist \
  Widgets/PrivacyInfo.xcprivacy \
  Widgets/NeuroForgeWidgets.entitlements

xcodebuild \
  -project NeuroForge.xcodeproj \
  -scheme NeuroForge \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project NeuroForge.xcodeproj \
  -scheme NeuroForge \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project NeuroForge.xcodeproj \
  -scheme NeuroForge \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The tests exercise all seven labs and seven purposes, every response schema, deterministic identities and scoring, typed-program bounds, reported-item isolation, source-grounded retrieval, semantic Markdown/LaTeX/code/table/HTML/RTF/structured-data/notebook/image parsing, selective table re-indexing, import gates, Shortcut consent/replay/prompt-injection/schema validation, offline question-bank quality, cancellation and cache expiry/bounds/recovery, baseline-only result reduction, continuous Today sequencing, immutable-attempt reflection supplements, asynchronous import/retry, adaptive baseline/reassessment replay and stopping, day-boundary/timezone-aware plans, weekly transfer, evidence reporting, onboarding persistence, export round trips, migration recovery, privacy deletion, English/Japanese runtime routing, notifications, Spotlight, content-manifest verification, and private-sync convergence.

Open `NeuroForge.xcodeproj` in Xcode for interactive app and widget testing.
The offline key-custody, manifest emission, signing, rotation, and verification procedure is documented in [Documentation/ContentSigning.md](Documentation/ContentSigning.md).

## External release gates

This repository is a code release candidate, not a signed App Store binary. The following records existing integration and distribution work. Each gate applies to the corresponding enabled capability or claimed offline edition. Shortcut deployment and the expanded offline-bank floor do not block independent integrated AI features; their release criteria are in the revised [QA chapter](Documentation/Improvement_Spec_2026-09-04/05_QA_and_Delivery.md).

1. **Signing and App Group:** the project selects automatic signing for team `34NS8XN5F9`, while command-line verification can still pass `CODE_SIGNING_ALLOWED=NO`. Provision `group.com.zacrotech.NeuroForge` for the app and widget, inspect the effective archive signature and embedded profiles, and verify widget snapshot sharing on physical devices before distribution.
2. **Production CloudKit provisioning and signed verification:** the code now includes the capability-gated private SwiftData configuration and a `CKSyncEngine` custom-zone original-file adapter using content-addressed `CKAsset` records, resumable protected state, deterministic merge/tombstone rules, per-document controls, background assistance, download materialization, and independently reported account/network/quota/service/partial-failure status. The source entitlement requests are present, but no unsigned build or plist declaration is capability attestation; the archived signature and provisioning profile are authoritative. Before advertising sync, register and associate the production container, enable Push Notifications, regenerate profiles, verify the signed entitlements, deploy the encrypted SwiftData fields before locking the production schema (CloudKit does not permit changing that state later), and pass signed physical-device account-isolation, multi-device, offline-resume, quota, conflict, deletion, zone-reset, migration, and restore tests. Any prerelease build distributed with earlier V1 model metadata also needs an explicit migration or a declared prerelease reset. No in-repo test can substitute for those production CloudKit checks.
3. **Existing optional Question Writer Shortcut verification, if distributed:** inspect the published three-action `NeuroForge Private Authoring` Shortcut at its recorded public URL, then test it on an eligible physical device with ChatGPT as the recommended **Use Model** selection and with another available selection. Cover fresh setup, repeat topic-only and consented source-backed use, callback queue draining, cancellation, timeout, malformed output, unavailable provider, excerpt bounds and source-link tampering, and offline fallback. Confirm that the app never claims to attest the user-selected provider, original files remain local, and the archived app does not contain `com.apple.developer.private-cloud-compute`.
4. **TestFlight and App Store review:** run signed device and TestFlight matrices across supported iPhone, iPad, and Mac configurations; complete screenshots, descriptions, age/category declarations, export-compliance answers, support/privacy URLs, App Store privacy metadata, and final accessibility/privacy review.
5. **Localization, catalog signing, and independent content review:** the code-level English/Japanese catalogs, placeholder checks, and literal inventory are complete, but a professional native-speaker review is still required. Before claiming/distributing that expanded offline edition, independently review the 7,000-question bank (including the 200 editorial retrieval concepts and all 800 computed retrieval instances across 80 calculation families), add its identities to the signed release inventory, bump the content version, and re-sign it in the approved offline environment—or obtain the signed release exception required by the product specification. Independently review every assessment answer, content-bank construct, evidence card, claim, and methodology reference before submission; the signed manifest proves integrity of the reviewed payload, not the correctness of unreviewed subject matter.
6. **Release validation evidence:** run the reference-device performance, scale, memory, accessibility, bilingual model-evaluation, visual-regression, and fatigue/usability matrices from the specification. Record any approved exception, complete TestFlight crash-free gates, and retain the signed release evidence bundle. Unit and simulator coverage cannot replace those device-, model-, and human-dependent checks.

Existing capability status describes the current implementation. The revised AI experience exposes availability or usage details when they affect a learner action, with technical verification details outside the normal learning flow.
