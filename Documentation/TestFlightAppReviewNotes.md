# TestFlight and App Review notes — 1.0.0 (5)

## Build 5 catalog update

- Expands the bundled offline catalog to 7,000 canonical questions: 1,000 in
  each of the seven top-level training labs.
- Mixed lab quizzes now draw from a persistent shuffled 1,000-question epoch
  without replacement, including across consecutive launches.
- Keeps adaptive Question Writer population fail-closed until the expanded
  catalog is independently approved and included in a signed release inventory.

## Internal TestFlight upload record

App Store Connect accepted build `1.0.0` (`5`) for TestFlight processing on
2026-09-03 at 22:10:52 EDT. This records the internal upload only; it does not
authorize external beta distribution or App Review submission, and it does not
replace the signed-device and CloudKit gates below.

These notes describe the current release-candidate UI. Do not attach them to a
submission until the signed-device and CloudKit gates at the end have passed.

## App Review note

NeuroForge is a daily STEM reasoning trainer. All core sessions and offline
question sets work without a model service. Optional external authoring uses one
user-installed Shortcut:

- Displayed in NeuroForge as **Question Writer**
- Named `NeuroForge Private Authoring` in the Shortcuts app
- Shared at `https://www.icloud.com/shortcuts/225ee5b407ed4bffbd3add2bf0c9ab8e`
- Action 1: **Get Question Writer Brief**, Request ID = **Shortcut Input**
- Action 2: Apple **Use Model**, Prompt = action 1 output; **ChatGPT** is the
  recommended user selection
- Action 3: **Submit Question Writer Result**, Request ID = **Shortcut Input**,
  Question Writer Output = action 2 **Response**

The shared artifact was published with **Cloud Pro** selected in action 2. The
reviewer may change the **Use Model** selection to ChatGPT, which NeuroForge
recommends, or to another model available in Shortcuts. This workflow is owned
and editable by the user. NeuroForge cannot select, lock, or attest the provider
or model version and records only that the Question Writer Shortcut returned the
result.

The user adds the Shortcut once. NeuroForge then opens it from the normal
**Create questions** action and receives the result through an authenticated
callback. Launch and callback URLs contain only opaque request data; the
provider prompt and response move through expiring app-managed storage and App
Intents. The returned set must pass the app's structure, topic-relevance,
answer-leak, repetition, and math-format checks before it can be reviewed or
practiced. Shortcut questions use recall → reveal → self-rate interactions, so
the provider's reference is not used as an independently verified scoring key.

The complete round trip requires an eligible physical iPhone or iPad, Shortcuts,
network access, and a model available to the current user in Apple's **Use
Model** action. Provider availability, account requirements, supported regions,
and capacity are controlled outside NeuroForge. The simulator can test offline
question sets but not the complete Shortcut/model round trip.

Topic-only briefs include no imported material. When a learner requests a set
from study material, NeuroForge identifies the selected sources, discloses the
excerpt limits, and asks before sharing bounded excerpts from those sources for
that run. It sends at most four excerpts, no more than 1,600 characters each or
4,800 characters total. The imported original,
unselected text, answers, and progress history remain local; the original file
is never attached to the Shortcut. Declining approval does not launch the
Shortcut.

For source-backed results, NeuroForge checks locally that every returned source
reference points to an excerpt approved for that exact request. This protects
the disclosure boundary but does not independently verify factual claims made by
the selected model.

NeuroForge contains no native PCC provider, no direct Foundation Models
authoring route, no third-party model API, and no managed PCC entitlement. The
only model route is the user-configured Shortcut. **Create offline instead**
remains available when setup, connectivity, Shortcuts, or the selected model is
unavailable.

Private iCloud sync is separate. It uses the current user's private CloudKit
database and iCloud storage quota. Original documents remain local unless the
learner separately enables original-file sync for that document.

## Reviewer steps

1. Complete the three-step onboarding flow.
2. Open **Train**. In **Question sets**, tap **Create set**.
3. Choose a starter set or enter `induction proofs` as the topic.
4. Tap **Add Question Writer Shortcut**. In Shortcuts, confirm the shared
   workflow is named `NeuroForge Private Authoring` and contains the three
   actions above. In **Use Model**, choose ChatGPT when it is available, add the
   Shortcut, and return to NeuroForge.
5. Tap **Create questions**. Confirm Shortcuts runs and returns to NeuroForge.
6. Confirm the returned questions can be reviewed and that an answer can be
   submitted, self-rated, and resumed safely.
7. Return to **Train** → **Create set** and create another topic set. The
   existing Shortcut should run without another installation step.
8. Import a PDF, image, text/RTF/HTML file, structured-data file, notebook, or
   source-code file in **Library**. Confirm it defaults to **Offline only**, then
   explicitly choose **Question Writer + offline**, select it while creating a set, and
   confirm the consent dialog identifies the selected source and states the
   limits before Shortcuts opens. Approve sharing and confirm the dialog states
   that sharing is limited to at most four excerpts, no more than 1,600
   characters each or 4,800 total.
9. Complete the source-backed run. Confirm each displayed source link resolves
   to material approved for that request and the original file was not attached
   to the Shortcut.
10. Start another source-backed run and decline source-sharing approval. Confirm
    Shortcuts does not open and the imported material remains available locally.
11. Tap **Create offline instead** and confirm a complete local set is produced
    without opening Shortcuts.
12. Cancel a running Shortcut or prevent its final action from returning.
    NeuroForge must retain setup, offer **Try again** and **Create offline**, and
    must not save a partial result.

## Internal submission gate

Before submission, run these steps with the exact archived/TestFlight build on
an eligible physical device, including fresh install, second run, cancellation,
timeout, malformed output, unavailable-model behavior, excerpt denial and
boundary cases, source-reference tampering, and callback queue draining. Test
ChatGPT available and unavailable, then repeat with a different **Use Model**
selection and confirm the app never claims to have verified the provider.
Confirm the archive does not contain
`com.apple.developer.private-cloud-compute`. Deploy and inspect the intended
CloudKit Production schema, then complete signed-device account switch,
multi-device, offline-resume, quota, conflict, deletion, and restore tests.
Update these notes if the Shortcut link, actions, UI labels, entitlements, or
build number changes.
