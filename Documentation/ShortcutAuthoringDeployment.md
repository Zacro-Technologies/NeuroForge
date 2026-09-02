# Question Writer Shortcut deployment

NeuroForge uses one external authoring route: the user-installed
`NeuroForge Private Authoring` Shortcut at
`https://www.icloud.com/shortcuts/225ee5b407ed4bffbd3add2bf0c9ab8e`.
The app does not contain a native Private Cloud Compute provider, call a model
API, or request the managed PCC entitlement.

Question Writer is a user-owned and user-configured workflow. The learner can
inspect or edit it and chooses the model in Apple's **Use Model** action.
NeuroForge recommends ChatGPT, but does not select, lock, or attest the provider
or model version. App provenance therefore identifies the Question Writer
Shortcut route, not a verified model provider.

## Published workflow and recommended configuration

The public Shortcut keeps its existing name and share URL. It has three actions:

1. **Get Question Writer Brief** with **Shortcut Input** as the request ID.
2. Apple **Use Model** with action 1's prompt. After installation, select
   **ChatGPT** as the recommended model.
3. **Submit Question Writer Result** with **Shortcut Input** and action 2's
   response.

The copy currently available at the public URL was published with **Cloud Pro**
selected in action 2. The learner may change that action to ChatGPT or another
available model. A release check must inspect the shared artifact and record its
actual default, but the app must not infer the provider from the template name
or the model the artifact had when published.

After one successful round trip, Question Writer is the default external
authoring route. NeuroForge passes only an opaque request ID in the launch and
callback URLs. The expiring, protected request mailbox holds the question brief
that the Shortcut retrieves; provider output is returned through the final App
Intent rather than embedded in a callback URL.

## Per-run study-material boundary

Topic-only briefs contain no imported material. Imported sources default to
**Offline only**. A learner must first change that source to **Question Writer +
offline**; the saved policy is never promoted during request construction. For
each document-backed run, NeuroForge must then identify the selected sources,
disclose the excerpt limits, and obtain explicit approval before preparing or
launching Question Writer. One run may contain:

- at most four excerpts;
- at most 1,600 characters in any excerpt; and
- at most 4,800 excerpt characters in total.

Only excerpts selected from sources approved for that run and their opaque
source references enter the expiring prompt. The consent record is bound
internally to the one-run request ID and each excerpt's exact chunk identity,
document version, and content hash. The mailbox stores and the validator uses the
exact bounded snapshots sent to the model, so a discarded tail cannot support a
returned claim and a large imported chunk cannot inflate the mailbox. Imported
originals, unselected text, raw answers, progress history,
attempt identifiers, and exact performance records remain local. The original
file is never attached to the Shortcut. Declining or cancelling the approval
leaves the material local and does not launch Question Writer.

Returned JSON must pass NeuroForge's local structure, topic-relevance,
answer-leak, repetition, and math-format checks. For a source-backed result,
every returned source reference must also resolve to an excerpt approved for
that request. This proves that the link is within the disclosed excerpt set; it
does not independently prove that a model's claim or reference answer is
factually correct. Shortcut questions therefore use recall → reveal → self-rate
interactions rather than treating the reference as a verified scoring key.
Offline authoring remains available when the Shortcut cannot run.

## Release verification

Test the shared workflow on an eligible physical device for fresh installation,
repeat use, callback delivery, cancellation, timeout, malformed output,
provider refusal, unavailable provider, and offline fallback. Exercise ChatGPT
both when available and unavailable to the current user, then repeat with a
different **Use Model** selection to verify that NeuroForge does not claim
provider attestation.

For document-backed runs, also test approval and denial, empty excerpts, four
excerpts at the individual and aggregate bounds, rejected fifth and oversized
excerpts, source-reference tampering, app backgrounding or termination, and
mailbox cleanup after success, failure, and timeout. Inspect the archived app
entitlements and confirm that `com.apple.developer.private-cloud-compute` is
absent.

## Native adaptive population boundary

The codebase includes a provider-neutral safety gate for a possible future
native route:

- every lab must first verify 1,000 unique bundled question fingerprints, and
  the exact bank version must be covered by the signed release inventory;
- profile and attempts are reduced locally to bounded performance, trend,
  calibration, review, preference, and session-length bands;
- raw answers, prompts, attempt/profile IDs, exact counts, and timestamps are
  excluded from the payload;
- off-device personalization requires separate current consent;
- study context is source-free by default and uses the same explicit per-run
  excerpt limits when enabled; and
- model output remains personal practice and cannot become baseline, holdout,
  or standardized scoring authority.

The installed Xcode 26.6 SDK exposes
`PrivateCloudComputeLanguageModel`, availability-gated to iOS/macOS 27, while
this project deploys to iOS/macOS 26.4. Availability-guarded source can compile
with that SDK, but the provider cannot execute on the project's 26.x deployment
OS and NeuroForge has no managed PCC entitlement. Do not advertise or enable a
native PCC route until the deployment target, runtime availability, entitlement,
network and quota handling, consent UI, signed archive, and fallback behavior
have all been verified. This future native route is separate from the
user-configured Question Writer Shortcut.
