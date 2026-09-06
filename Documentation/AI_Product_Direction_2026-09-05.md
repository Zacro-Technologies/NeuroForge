# NeuroForge product direction — 5 September 2026

**Owner direction: AI is central; local processing exists for useful offline operation.** This is a documentation and specification revision. It does not implement, deploy, enable a provider, or certify any new AI capability.

NeuroForge should help a learner study and reason with AI throughout the experience: understand a topic, discuss a source, attempt a problem, explain an answer, receive a useful grade, address a mistake and choose what to learn next. The model is a substantive tutor, evaluator and learning-content creator. Exact arithmetic, formal logic and other reliable programmatic tools remain part of that experience where they are the right evaluators.

Local processing makes practice responsive and available without a connection. It is not a privacy-led mission, a prohibition on cloud processing or a reason to make AI peripheral. Automatic routing may use relevant selected sources, the current answer and learning history through configured local or cloud services. Keep ordinary service settings understandable; do not insert a separate model-boundary or repeated source-consent workflow into every learning action. Existing explicit user settings and normal platform requirements still apply.

## Decisions that replace the earlier premise

| Area | Earlier product restriction | Revised requirement |
|---|---|---|
| Product identity | Deterministic trainer with optional AI authoring | AI-centered STEM learning, tutoring, evaluation and personalized practice |
| Local processing | Privacy-first/local-only source policy | Reasonable offline availability, responsiveness and continuity |
| Model access | User-owned Question Writer Shortcut as the only model route | Integrated local and cloud model services; Shortcut remains an optional adapter |
| Short answers and explanations | Keyword matching or compulsory reference/self-rating | Semantic AI rubric grading, partial credit, criterion feedback and grade review |
| AI and progress | Model results categorically excluded from learning decisions | Accepted AI grades support appropriate practice progression, review and coaching; standardized comparisons depend on evaluated protocol quality |
| Source study | Bounded external authoring plus self-check | Source-grounded Q&A, summaries, question sets, graded recall, explanations and targeted review |
| Planning and diagnosis | Only fixed rules may prescribe or explain a plan | AI can propose plans, diagnose mistakes and explain recommendations; accepted plans obey the learner's constraints and remain stable |
| Offline fallback | Every result must be deterministic and immediately scoreable | Available exact/local-model evaluation; otherwise preserve a pending answer, offer useful offline work or optional self-check, and resume evaluation later |
| Provider gate | Complete offline inventory before admitting native AI | Evaluate AI features on their own quality/availability criteria while retaining honest offline inventory claims |
| History | Recompute only deterministic scores | Replay retained accepted exact/AI grades; retain append-only re-evaluations and their evidence |
| Delivery sequence | Complete deterministic foundations before AI | First slice includes a tutor, an AI-graded written explanation, source context and interruption/offline recovery |

## Required AI experience

1. A tutor available from the active task, selected source and progress context, with follow-up questions and explanations suited to the learner.
2. AI grading for short responses, teach-back, reasoning, critique and other rubric-based answers; recognize equivalent meaning and missing or contradictory ideas, not just keywords.
3. Progressive hints, comparisons of solution approaches, worked explanations and fresh follow-up practice, while recording assistance when it changes interpretation of performance.
4. Source-grounded Q&A, summaries, generated study sets and graded retrieval with inspectable citations and useful personal-source progress.
5. AI-assisted goals, plans, error-pattern diagnosis, review recommendations and progress coaching that refer to actual work and respect the learner's time and preferences.
6. Interpretation of supported handwritten work, diagrams and images, with a chance to correct extracted content before submission or grading.

The normal interface emphasizes the question, the learner's reasoning, feedback and next step. Provider identifiers, prompt versions and raw evaluation metadata are available in details; show route limitations, costs or uncertainty when they affect a decision.

## Quality and restraint

The owner expects tasteful, high-quality features whose interactions are thought through. AI should make the learning experience more capable and coherent. Each feature must identify a specific learner need, an appropriate moment to help and an observable benefit. Evaluate the actual output and interaction against a straightforward existing or proposed way of completing that task; generation volume, visible AI branding and model-call count are not success measures.

Integrate grading into submission and feedback, explanation into the current problem, and source help into reading and study. Ordinary practice does not require a chat conversation. Keep one clear primary action, use concise feedback with optional depth, and avoid repeated AI badges, competing suggestion cards, unsolicited chat openings or decorative generation. Contextual suggestions are dismissible and do not reappear for the same unchanged work.

Quality review covers factual and grading accuracy, teaching usefulness, meaningful question variety, fit to the learner's task, visual polish, accessibility, response time and complete loading/error/offline behavior. Inspect ordinary, difficult and failed cases in the real interface. Refine features that produce generic advice, repetitive exercises or distracting friction before expanding their variants. The full AI feature ambition remains; each capability must earn a polished place in the experience. PRD-011, UX-019 and QA-REQ-028 make this an acceptance requirement.

## Grading and offline behavior

An AI grader evaluates a frozen question, rubric, reference/source context and submitted answer. The accepted result contains criterion outcomes, partial credit where defined, a concise explanation and identified uncertainty. It can affect normal learning progression within the tested task and evaluator scope. An AI grade is distinct from a learner's self-rating; neither is automatically a standardized population measure.

Save submitted work before beginning model evaluation. Retain the accepted result and its evaluator/rubric provenance. Closing the app, a late reply, a retry or a model update must not attach a grade to a different answer or silently change earlier grades. A learner can question a grade or ask for review; any accepted change is a separate recorded revision.

Offline operation guarantees useful downloaded/authored practice, access to saved sources and feedback, local editing/saving/history and exact continuation. Use local AI when its task/language capability is adequate. If it is not, keep a pending evaluation and offer available activities or optional labeled self-check. Waiting for a model never creates a wrong answer or a learning penalty. Advanced cloud features do not have to pretend they have full offline parity.

## Specification authority and implementation status

The [improvement master v1.1](Improvement_Spec_2026-09-04/README.md), its five owning chapters and the revised [product specification](../NeuroForge_Release_1.0_Product_Spec_System_Design_Development_Plan.md) express this direction. The generated [complete specification](Improvement_Spec_2026-09-04/Complete_Specification.md) and [requirement index](Improvement_Spec_2026-09-04/Requirement_Index.md) are rebuilt from those source chapters.

Earlier audits, implementation notes, test reports and deployment guides describe the previous app and remain historical evidence. Their references to deterministic-only grading, Shortcut-only authoring and privacy-led restrictions do not override this revision. Existing test passes establish only the behavior they actually exercised. Changed requirements are reset to specification/reassessment status in the current traceability ledger; unchanged historical evidence is retained.

No application source, runtime behavior, provider configuration, credentials, content bank, application test or deployment is changed by this revision. Implementation planning must be updated against the new acceptance contracts before coding resumes.
