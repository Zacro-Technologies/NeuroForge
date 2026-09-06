# 02 — Content, question quality, and scoring specification

**Status:** proposed implementation specification, based on QA executed on 4 September 2026 and revised for the AI-centered product direction on 5 September 2026. Requirements using **must** describe the intended replacement behavior. They do not describe capabilities already delivered. No application implementation is included in this chapter.

**Scope:** AI-generated learning content, semantic rubric grading of short/free-text responses, contextual feedback and tutoring, exact exercise evaluators, editorial production, the eight existing response types, answer equivalence, grade review, item identity, the mixed offline banks, all 58 existing catalog activities, and seven complete worked examples. The adaptation chapter owns learner estimation and scheduling policy. The application/state chapter owns persistence transactions and migrations. The interaction chapter owns controls, layouts, and accessibility implementation. Those implementations must preserve the content and scoring invariants defined here.

## 1. Evidence and the outcomes this chapter must deliver

The executable evidence is recorded in [ExecutedProbeResults.txt](../QA_2026-09-04/ExecutedProbeResults.txt). Six content probes executed the application generators and scorer; the bank probe checked 4,000 actual identities. Their passing assertions confirmed defects in the current application. Passing those investigative probes is **not** a release acceptance criterion: the eventual regression tests must assert the corrected behavior.

| Evidence ID | Confirmed current behavior | User consequence | Requirements that replace it |
|---|---|---|---|
| QA-C01 | Spatial seed 11 produces two `(-10, 10)` choices; one receives full credit and one receives none. | A correct answer can be penalized arbitrarily. | CON-006; SCO-006; QA-S01 |
| QA-C02 | Science seed 8424208090942894707 calls intervals 18–26 and 27–35 overlapping; 266 of the 1,000 science bank items have this contradiction. | The lesson contradicts its own evidence and teaches an unreliable inference. | CON-007; EX-C104; QA-S02 |
| QA-C03 | The canonical arithmetic-mean wording passes, while “Sum all observations then divide by their count” fails; `2*x` and `4x` fail equivalent derivative questions. | The app rewards guessing its wording over understanding. | SCO-003; SCO-009 through SCO-013; QA-S03 |
| QA-C04 | `f(b)-f(a)` receives full credit when the question defines `F′=f` and requires `F(b)-F(a)`. | The app accepts a substantively wrong mathematical answer. | SCO-010; SCO-011; QA-S04 |
| QA-C05 | An explicitly accepted `yes` instead of `plausible` yields `isCorrect=true` and credit 2/3. | Feedback and recorded achievement disagree. | SCO-001; SCO-015; QA-S05 |
| QA-C06 | Transfer contains 986 rate-product questions; Logic contains 990 stale-state traces; Science contains 557 mean mappings and 436 interval questions. | Distinct numbers feel like the same question repeatedly. | CON-014 through CON-019; QA-B01 through QA-B06 |
| QA-C07 | Retrieval has 101 different targets delivered as the same fixed retrieve/compare/locate/retry sequence. | Completing a generic workflow is counted as exposure to a knowledge target without eliciting that knowledge. | CON-010; CON-016; CON-026; QA-F48 |
| QA-C08 | Source inspection shows solution cues in context and representations rendered before answers, including protected checks. | Baseline and independent practice can be answered from a supplied solution cue. | CON-004; CON-008; QA-S06 |
| QA-C09 | The same seed at target difficulty 0.2 and 0.9 produces identical problem, response contract, representations, and ID; metadata alone changes. | The requested challenge level does not necessarily change the task. | CON-011 through CON-013; family matrix |

The implementation outcome is an AI-centered question and teaching system in which a learner can ask for a topic or source-based lesson, answer naturally, receive meaningful rubric feedback, discuss their reasoning, challenge a grade and continue with appropriately targeted practice. AI generation and grading are normal learning features. Exact evaluators remain valuable for arithmetic, symbolic domains, geometry, choice sets and executable logic where they provide stronger correctness checks.

Local processing supports reasonable offline use, responsiveness and continuity. It does not impose a blanket local-only or deterministic-only rule on teaching or grading. Capable local models and cloud models may both generate questions, grade explanations and tutor; the route depends on capability, connectivity, quality, latency and configured cost. Saved learning materials, original responses and completed grades must remain readable offline. An unavailable AI service leads to pending grading, retry, an available local route or explicit self-check, never a fabricated incorrect answer. The chapter does not claim any resulting change in general intelligence or externally validated psychometric performance.

## 2. The authoritative exercise contract

<a id="con-001"></a>

### CON-001 — One contract must drive generation, rendering, validation, and explanation

Replace the implicit relationship between strings, answer keys, and metadata with an explicit authoritative contract. Retain adapters to `NFExercise` and `NFExerciseInteraction` during migration; do not require a simultaneous rewrite of every screen. The new contract must be able to serialize and round-trip the following fields without losing meaning.

| Field group | Required content | Consumer and invariant |
|---|---|---|
| Identity | `semanticProblemID`, `semanticFingerprint`, `contractRevision`, `familyID`, `objectiveID`, `structureID`, `generatorVersion`, canonical parameters, content-edition ID | Novelty is tied to the problem, not a display UUID, option order, language, or difficulty label. |
| Task | Plain-language question, requested deliverable, essential givens, assumptions, domain restrictions, answer format, units | The question is answerable from the intended prerequisites plus these givens. |
| Objective | One primary operation; optional explicitly weighted subordinate operations; prerequisite concept IDs | A workflow or confidence exercise cannot silently become evidence that an unrelated fact was recalled. |
| Representations | Structured table/chart/geometry/code/equation data; role of each representation; accessible equivalent | All visible claims, summaries, and accessible descriptions derive from the same underlying data. |
| Answer authority | Response contract and evaluator kind: exact, AI rubric, combined, or self-check; semantic alternatives, required criteria, forbidden assertions, partial-credit policy, supporting reference and rubric version | Rendering does not invent an answer. AI grades judge the response against the saved criteria and evidence; learner self-ratings remain a separate result kind. |
| Assistance | Essential givens, optional hint stages, worked solution, reference material, allowed teaching modes | Solution-bearing material is unavailable before an independent response. |
| Difficulty intent | `editorialBand` B1–B4, `demandVector`, prerequisite demands, named parameter bounds, reason for each demand | A level describes actual task demands and is separately identified from empirical difficulty estimates. |
| Feedback | Correct reasoning, shortest decisive step, criterion feedback, contextual AI explanation, next attempt recommendation | Feedback addresses the actual response and retained evidence; unsupported diagnoses are qualified rather than asserted as fact. |
| Provenance | Authored or AI-generated origin, generation/rubric/evaluator versions, retained source references, relevant author/reviewer records, verification method and model/route metadata for AI work | The question and saved grade can be inspected later without rerunning a model or pretending dynamic AI output was individually human-approved. |
| Delivery | Eligible modes, `independentEligible`, `protectedEligible`, compatible response forms, time eligibility, novelty relationship, required assets, locale support | Unsupported forms and missing assets are excluded before reservation. |

A suggested implementation shape is a versioned `NFExerciseContract` containing a discriminated `NFAuthoritativeResponseContract`, an `NFStimulusModel`, and `NFContentReviewRecord`. These names are proposed types, not assertions about existing APIs. Prefer typed values and enums to adding more magic strings to tags. `NFExercise` may initially remain the rendered/session object produced from that contract.

<a id="con-002"></a>

### CON-002 — Generation must produce a coherent task, reference and rubric

Use AI to create question sets, examples, explanations, source recall and follow-up tasks from learner goals, selected material and recent learning needs. Every accepted task must retain its prompt, actual givens, requested deliverable, response form, difficulty intent, rubric, reference evidence and provenance before the learner answers. Generation must not invent its grading standard after seeing the response. Source-driven generation should use the supplied passages and preserve useful citations; broader subject knowledge must be distinguished from what the selected source says.

For exact generated families, follow this order: select an eligible family and demand specification; draw bounded substantive parameters; derive the stimulus model; derive the answer with an independent or independently checked method; construct and validate alternatives; select compatible representations; render localized task text; validate the complete item. The seed and generator version must reproduce the rejection as well as valid outputs. For AI-generated tasks, retain the accepted generated artifact and generation configuration; do not promise that rerunning a model with the same seed recreates its prose. Check schema, required assets, source support, ambiguity and rubric sufficiency, using exact tools for any computable components. A rejected candidate must not reach a session.

Runtime AI practice does not require every question to be pre-authored or individually signed into the bundled offline inventory. Its creation and evaluation policies need meaningful quality evaluation, and its results retain their origin. The reviewed standardized bank and protected skill-check forms retain their own admission requirements. This distinction preserves usable AI generation without falsely describing it as a pre-reviewed standardized item.

For exact generators with finite small domains, release tooling must enumerate the whole domain. For larger domains, it must enumerate all boundary partitions and run a deterministic property sweep. “The canonical answer scored as correct” is necessary but cannot replace independent truth checks. Calculation chains must have an independent arithmetic oracle; cube nets must be checked by geometric folding rather than a hand-maintained opposite-face list; logical patches must be executed by the restricted interpreter against the contract's test inputs.

<a id="con-003"></a>

### CON-003 — Generation failure must remain a content failure

A runtime content error must produce a replacement reservation or a clear inability to continue, never an incorrect score for the learner. Keep a reason such as `duplicateAnswer`, `noValidInterpretation`, `missingAsset`, `unsupportedLocale`, `oracleMismatch`, or `ungradableResponseContract`. AI timeout, model unavailability, insufficient source context and invalid output are generation failures with Retry or another supported learning route. Record the content identity, family or generation request, generator/model and contract revision. Preserve the relevant source and question with the study record; general diagnostics should use bounded identifiers and failure details rather than duplicating whole documents. A repeated failing family is quarantined for the current session; the reservation rules in section 6 determine what can replace it.

<a id="con-004"></a>

### CON-004 — Every representation needs a declared instructional role

Use four roles: `essentialGiven`, `optionalPracticeHint`, `postResponseReference`, and `workedExample`. An independent item may initially render only essential givens. An assisted-practice item may expose an explicit requested hint, which records assistance without changing the original submitted response. A teaching example may show all roles and must not record an unaided performance result. A picture or equation cannot evade this rule by being stored in a different field.

The counterexample `2×3=6`, the conclusion “the divisor is zero,” and a fully stated best experiment are post-response reasoning or teaching scaffolds when the question asks the learner to derive them. They are not essential givens merely because they are useful to read. A domain restriction such as `a=b≠0`, by contrast, is an essential given.

<a id="con-005"></a>

### CON-005 — An item must state what is being judged

The contract must identify whether it judges a final value, exact representation, method, explanation, uncertainty interpretation, minimal counterexample, or a set of simultaneous criteria. Instructions must not request three deliverables when the scorer grades one. Do not ask “estimate” while silently requiring one exact string. Do not ask “which experiment?” while grading the order of generic study steps. If more than one answer is valid, encode exact alternatives or a semantic rubric that accepts the valid reasoning. Open-response rubrics must describe necessary concepts and reasoning without demanding one model sentence, one writing style or an arbitrary response length.

## 3. Correctness, ambiguity, and content quality

<a id="con-006"></a>

### CON-006 — Every selectable alternative must be semantically distinct

Before shuffling, canonicalize every option under the response domain. Coordinate choices use typed tuples, numerical choices use exact quantities, formulas use the restricted symbolic equivalence checker, and prose choices use editorial equivalence annotations plus a duplicate-text check. Reject any distractor equivalent to an accepted answer or another distractor. Unique IDs are insufficient.

For coordinate rotation, the generator may keep a valid symmetric input such as `(10,10)` and generate a different misconception-based distractor; it need not exclude symmetric points. Candidate distractor transforms include clockwise rotation, origin reflection, or unchanged input, but each actual result must be rechecked because transformations can coincide on axes or the origin. If the number of distinct meaningful alternatives falls below the required count, reduce the declared choice count where allowed or reject that parameter set. Never keep an indistinguishable option and score by its hidden ID.

<a id="con-007"></a>

### CON-007 — Statistical interpretations must follow the estimand and procedure

Replace the current generic “overlapping uncertainty prevents a definitive effect claim” rule. An interval-bearing task must declare the quantity being estimated, interval type, level if applicable, sampling/design assumptions, and whether the question is descriptive, inferential, or causal. If that information is intentionally missing, “the interval type/procedure is unspecified” must be a supported limitation; do not infer its meaning.

The interval object must store endpoints numerically. `overlap` is a derived geometric fact: closed intervals overlap when the maximum lower endpoint is no greater than the minimum upper endpoint. Touching at an endpoint is recorded separately from positive-length overlap for explanatory precision. This flag must not itself determine statistical significance, causal identification, or equivalence. Comparing two individual confidence intervals is not a substitute for analyzing the difference of interest. [Altman and Bland, *Interaction revisited: the difference between two estimates*](https://www.bmj.com/content/326/7382/219) explicitly discusses the mistake of interpreting overlap as proof of a nonsignificant difference.

For an inference about a mean difference, either provide a reviewed interval for that difference or provide the data and a fully specified supported calculation. Its interpretation depends on that procedure. Failure to exclude zero does not establish equality; exclusion of zero does not establish practical importance or causation. A causal conclusion additionally needs a defensible assignment/design argument. A randomized study can still have a limited target population. A plot of observational group means cannot answer every one of these questions.

A generated raw dataset, displayed mean, interval, narrative, answer key, and accessible description must agree. If intervals are deliberately supplied independently of the raw dataset for an elementary reading task, explicitly identify them as supplied model summaries and do not imply that the displayed observations generated those intervals. Prefer computing all summaries from the same reviewed dataset and method.

<a id="con-008"></a>

### CON-008 — No pre-answer solution leakage in independent modes

A release test must generate every family in each protected purpose and inspect both visual and accessible content roles. It must fail if a hidden answer is repeated in a pre-answer caption, graph summary, equation, hint, alt text, source citation excerpt, table heading, or placeholder. Accessibility needs equivalent information, not a more revealing solution. Removing a necessary graph description is also unacceptable: accessible stimuli must preserve the task while describing essential data.

<a id="con-009"></a>

### CON-009 — Distractors must express plausible errors

Each distractor must have a declared misconception ID and a one-sentence explanation of why that error produces this specific alternative. Generic “always,” “ignore the evidence,” or obviously unrelated text is insufficient for a mature question bank. For a time-unit question, distractors should be comparable units such as minute, hour, or day under a clearly stated SI-base-unit question, not three paragraphs about reversed relationships. For an experimental design item, rival options should each fix some limitations while failing the decisive one.

Correct options must not be identifiable by consistently being longer, more qualified, grammatically compatible, more technical, or the only option containing numbers. These properties are lint warnings for editorial review, not a reason to distort naturally necessary wording. The release record must document any exception.

<a id="con-010"></a>

### CON-010 — A response form must perform the operation its name promises

Cloze requires a real omitted element with enough context to make the omission resolvable. Equation reconstruction requires a specific equation with a meaningful slot. Figure interpretation requires a figure or structured data whose content matters to the answer. Code tracing requires inputs and control flow that determine an output. Paper Sprint requires an actual bounded abstract. A repair-cycle task must involve an actual response discrepancy and a target-specific retry, or be explicitly classified as learning-method practice with no credit for the knowledge target.

A target must declare `compatibleRenderings`; unsupported renderings are unavailable rather than synthesized as generic `E_source+C_stated→□` text. Generating a new rendering does not create a new knowledge target.

<a id="con-011"></a>

### CON-011 — Editorial difficulty must be based on real demands

Define four initial editorial bands: **B1 Foundation**, **B2 Developing**, **B3 Challenging**, and **B4 Advanced within this family**. These are intended demand categories, not percent-correct predictions or psychometric thresholds. Each family must specify actual changes in at least one of: number of dependent steps, number of relevant variables, prerequisite concepts, representation conversion, distractor similarity, uncertainty to resolve, size of the search space, or amount of scaffolding. The family matrix in section 9 supplies the required starting definitions.

Do not increase difficulty solely by adding a long story, awkward numbers, tiny controls, unfamiliar vocabulary unrelated to the target, or time pressure. Larger arithmetic may be a legitimate demand in an arithmetic family, but must not be used as the primary difficulty control in a causal-reasoning question. All levels retain readable language and accessible representations.

<a id="con-012"></a>

### CON-012 — Difficulty requests must select valid demand specifications

The adaptation layer supplies an intended level/demand request and relevant prerequisites. The content layer must return the selected actual demand vector and a reason if the request cannot be met. It must never label an unchanged exercise “advanced” simply by replacing `difficulty.overall`. Same seed plus different demand specifications should produce a predictably different contract where substantive content differs; if the request maps to the same supported demand bin, report the same level honestly.

Protected difficulty equivalence across alternate forms requires explicit review. A short recognition item is not automatically equivalent to free recall of the same relationship. Maintain empirical statistics separately by format, assistance, context, and level until evidence supports aggregation.

<a id="con-013"></a>

### CON-013 — Editorial and empirical difficulty must remain separate

Store `editorialBand` and `demandVector` independently from `empiricalDifficultyEstimate`, `calibrationStatus`, calibration version, sample size, eligibility rules, uncertainty, and model version. No value in this chapter is an externally validated item parameter. The proposed quotas, level labels, score weights, and parser limits are engineering or editorial decisions that require evaluation. Low observed success can indicate a bad question, input friction, or missing prerequisites as well as genuine challenge. Item difficulty updates must not silently rewrite historical contracts.

## 4. Scoring authority and result semantics

<a id="sco-001"></a>

### SCO-001 — Correctness and credit must be consistent

A fully accepted authoritative response must have `isCorrect=true` and `credit=1`. An accepted equivalent is not partial knowledge. A partial response must have `isCorrect=false`, a declared partial-credit basis, and component results explaining the missing or contradictory parts. An incorrect response has `isCorrect=false` and credit zero unless the declared rubric deliberately awards component credit. A skipped, unsubmitted, invalid-item, ungradable, or self-reported response must not be encoded as an objective incorrect/correct binary.

Introduce versioned outcome distinctions equivalent to `correct`, `partial`, `incorrect`, `needsClarification`, `pendingGrade`, `needsReview`, `selfReported`, `skipped`, and `invalidItem`, with an independent evaluator-kind field such as exact, AI rubric or combined. An accepted AI rubric grade may be correct/partial/incorrect and contribute to normal learning progression; it is not a self-report. Its evaluation method must remain inspectable and must not be represented as mathematical proof or externally validated assessment accuracy. The state chapter owns the persistence representation. Existing boolean/credit fields may be adapter outputs, but they cannot erase the distinction from new records. `needsClarification` means the submitted notation or a material part of its meaning cannot be interpreted reliably; it is not a euphemism for a confidently wrong answer.

<a id="sco-002"></a>

### SCO-002 — Scoring must produce an inspectable component result

For each component store the submitted value, parsed interpretation when applicable, criterion/rule version, evaluator kind, outcome, awarded/max credit, cited response evidence, source support where relevant, misconception code if supported, and a learner-safe explanation. Preserve the original response alongside normalized interpretation. Feedback must not claim a specific misconception solely because an arbitrary wrong number matches no known case; use “Recheck the conversion” unless there is diagnostic evidence for a direction or scale error.

Exact evaluation must be deterministic and side-effect free for a given contract revision and response, independent of theme, option order, connectivity and irrelevant locale presentation. AI rubric evaluation can use a capable local or cloud model and is not required to be mathematically deterministic. Its output must be checked against the response/criterion identities, required result fields, credit bounds, reference support and declared grading policy before acceptance. A combined task preserves each component's evaluator; AI cannot silently overwrite a computable component's verified value.

Freeze and save an accepted AI grade with the exact submitted response, question/rubric versions, source context or references needed for review, evaluation configuration and model/route identity where available. Reopening history, reconnecting or changing a provider displays the saved result, not a newly inferred grade. Retrying an unfinished request cannot create a second completed attempt; a requested reevaluation creates a linked grade revision with a reason. An accepted reviewed revision may update effective learning progress under the correction policy while preserving the original record. AI wait time is excluded from answer-solving time; elapsed time is never an undeclared grading criterion.

<a id="sco-003"></a>

### SCO-003 — Parsing policy must follow the answer domain

Replace a single universal text normalizer with explicit domains: natural-language phrases, exact numbers, fixed-unit quantities, unrestricted-unit quantities within an allowed dimensional family, identifiers, symbolic expressions, coordinate tuples, ordered labels, and booleans. Case folding is acceptable for ordinary English prose and some reviewed textual aliases. It is not generally safe for variables, named functions, units, chemical symbols, or source-code identifiers.

For exact domains, parsing stages are lexical normalization, syntactic parsing, domain validation, semantic equivalence, and rubric evaluation. Reject unsupported exact syntax before claiming equivalence. Natural-language responses use semantic AI rubric interpretation where appropriate; ordinary paraphrase is not a parser failure merely because it is outside a local synonym list. Do not execute user text. Do not silently drop operators, exponents, grouping, signs, decimal points, primes, or unit prefixes. Preserve the complete parse and interpretation for feedback when notation could be surprising.

<a id="sco-004"></a>

### SCO-004 — The eight response types remain the stable surface contract

The following rules cover the existing `numeric`, `singleChoice`, `multipleChoice`, `orderedSteps`, `shortText`, `selfCheck`, `claimEvidence`, and `logicState` enum cases. More specialized typed contracts may be carried inside these cases or introduced by a versioned adapter; this chapter does not require proliferating interaction types merely to fix grading.

| Existing type | Accepted example | Rejected or non-objective example | Required interpretation |
|---|---|---|---|
| Numeric | EX-C01: for 1,250 mm in a field labeled metres, `1.25`, `1.250`, `5/4`, or `1.25e0` | `1250`, `1.25 cm`, `1/0`; uninterpretable `1,25` under an ambiguous locale policy requests clarification | Exact numeric value plus declared unit/representation policy. |
| Single choice | EX-C02: select the unique option representing a 90° counterclockwise rotation of `(10,10)`, namely `(-10,10)` | An equivalent duplicate option is a content error, never a learner error | Options validated semantically before ID-based selection scoring. |
| Multiple choice | EX-C03: when A and C are the two safeguards, select exactly A and C | Selecting A, C, and “remove inconvenient outcomes” is not fully correct | Exact set for full credit; explicit optional partial rule. |
| Ordered steps | EX-C04: a proof follows all declared dependency edges; two independent preparation steps may be swapped | A conclusion preceding a required derivation violates its edge | All valid topological orders accepted when order is partial. |
| Short text | EX-C05: “Sum all observations then divide by their count” for arithmetic mean; `4x` for derivative of `2x²` | “Divide the count by the sum”; `f(b)-f(a)` when F is the required antiderivative | AI semantic rubric for explanations; exact symbolic evaluation where supported; combined criteria when the task asks for both. |
| Self-check | EX-C06: learner recalls, reveals, then records “partly matched” with a specific omitted condition | Clicking “matched” is not independently verified objective correctness | Self-reported reflection and exposure only. |
| Claim/evidence | EX-C07: attach group means to an observed-difference claim and assignment information to a causal-limit claim | A larger observed mean alone supporting “treatment caused every increase” | Satisfy declared support constraints without unsupported edges. |
| Logic/state | EX-C08: final typed state `count=9`, `ready=true`, violated invariant `readyMatchesCount` | `count=9`, `ready=false`; an accepted alias yielding partial credit | Per-field domain parsing and full credit for accepted equivalent states. |

<a id="sco-005"></a>

### SCO-005 — Numeric responses require exact and approximate contracts

Use the existing exact-rational machinery as the preferred authority for integers, terminating decimals, rational arithmetic, proportions, and exact unit conversions. A displayed decimal approximation must not silently replace an exact rational key. For a task explicitly requiring a rounded answer, define the rounding rule and precision, then judge that deliverable. For an approximation task, define the accepted interval numerically, including boundary inclusivity, instead of a handful of strings.

EX-C01 asks: “Convert 1,250 millimetres to metres.” The response control visibly supplies `m`. Accept `1.25`, `1.250`, `5/4`, and `1.25e0`; preserve the learner's original notation. Reject `1250` as a value error. If the learner explicitly submits `125 cm`, the quantity is equivalent but the requested representation is not metres: return a representation component error if that is an assessed objective, otherwise convert and explain according to the contract's predeclared mode. Do not decide after seeing the answer.

Reject NaN, infinity unless explicitly meaningful in a separately reviewed domain, denominator zero, overflow, impossible unit combinations, and expressions outside the allowed grammar. Percentages distinguish a probability from a percentage: `0.25` in a probability field and `25` in a percent field can denote the same ratio, but `0.25%` does not equal `25%`. Negative zero normalizes to zero unless signed zero is explicitly part of an advanced computing objective.

<a id="sco-006"></a>

### SCO-006 — Single-choice scoring requires a unique semantic answer

After CON-006 validates the options, selected option ID may identify the selected semantic value. Unknown/stale option IDs are invalid responses and must not crash or select a default. Duplicate display text, equivalent formula answers, and multiple defensible prose choices invalidate the item before presentation. If a previously shipped duplicate is discovered during a session, suppress objective scoring and replace the item; do not force the learner to guess an internal ID.

<a id="sco-007"></a>

### SCO-007 — Multiple-choice credit must be explicit and resistant to selecting everything

Full credit requires exactly the accepted set, or one of the explicitly accepted alternative sets. The default for independent assessment is exact-set grading. If a practice task declares equal-weight component credit, use `max(0, (correctSelections − incorrectSelections) / requiredSelections)` with a maximum of 1; this is a proposed transparent instructional rule, not a validated ability model. The rule must not be used when the number or cost of wrong actions makes equal weights inappropriate.

For EX-C03 with two correct and two incorrect options: A+C earns 1; A earns 0.5 only in a partial-credit practice contract; A+C+one incorrect earns 0.5; selecting all four earns 0. Exact-set mode awards zero for all but A+C. Feedback identifies every missed safeguard and every harmful selected action. Do not show “correct” for a partially completed set.

<a id="sco-008"></a>

### SCO-008 — Ordered steps must represent dependency rather than stylistic preference

Add an ordering authority capable of a single order or a dependency DAG. Full credit requires all required nodes exactly once and every required edge satisfied. For a graph with independent A and B both preceding C, A-B-C and B-A-C are accepted. Repeated/missing/unknown steps cannot receive full credit. Detect cycles in authored graphs as a release error.

If partial credit is permitted, score the fraction of required dependency edges satisfied, with separate mandatory completeness validation. When the graph has no edges, every complete permutation is correct; do not divide by zero or invent positional penalties. Do not award a nearly full score to a response that omits the decisive step merely because remaining nodes are conveniently positioned. For a strict algebraic proof, the dependency graph may legitimately reduce to one chain. A generic preferred reading order is a learning strategy exercise; it must not be presented as a uniquely valid theorem about how all experts read papers.

<a id="sco-009"></a>

### SCO-009 — Short responses use the evaluator suited to their meaning

Use exact normalized aliases for genuinely constrained labels, explicit identifier parsing for code names, typed mathematical parsing for supported formulas, and AI semantic rubric grading for short explanations, free recall, teach-back, scientific reasoning and method justifications. A 280-character limit may remain for concise responses, but it is a UI limit and cannot justify truncating input silently. Validate the length before commitment; preserve the complete original until the learner edits it.

AI grading is a required normal path for explanatory prose. The task's saved rubric defines what counts as a correct, partial or incorrect answer; the model evaluates meaning, relationships, required conditions, omissions and contradictions rather than surface wording. Valid paraphrases and equivalent explanations receive full credit without requiring a pre-enumerated alias. Brevity, spelling variation and writing style must not reduce subject-knowledge credit unless they are stated assessment criteria.

Accepted AI grades can inform topic progress, adaptive practice, review scheduling and targeted coaching under the core learning policy. They are separate from learner self-ratings and from exact computational proof. Protected assessments may use AI-graded components when their particular evaluation method has met that assessment's quality requirements; the presence of a model is not by itself a blanket ban, and ordinary AI learning must not wait for protected-assessment validation.

If required evidence is absent, the answer is materially ambiguous or the evaluator cannot produce a supported grade, preserve the response as needs clarification/review or pending grading. Offer a specific clarification, Retry, an available capable local/cloud evaluator, or learner-selected self-check. Do not force every natural-language answer into self-check because the exact parser cannot handle it. A model timeout or unsupported device is never evidence that the learner was wrong.

<a id="sco-010"></a>

### SCO-010 — Restricted symbolic equivalence must preserve symbol roles

Initially support rational coefficients, declared variables, addition, subtraction, multiplication, division, parentheses, and bounded integer powers for families whose mathematics falls inside that grammar. Treat implicit multiplication (`2x`), explicit multiplication (`2*x`), and the multiplication glyph (`2×x`) as equivalent when the tokenization is unambiguous. Normalize `x^1` to `x` and multiply exact rational coefficients. Accept `4x`, `4*x`, and `2x+2x` for the derivative of `2x²` on its stated real domain.

The contract must provide a symbol table. For EX-C05b, `F` is a named antiderivative function and `f` is the integrand; they are distinct. Function application `F(b)` is not multiplication `F*b`. Prime notation must refer to a declared derivative relation and cannot be stripped as punctuation. Coordinate labels and dummy variables may be renamed only when the contract declares an alpha-equivalence rule; never infer that all letters differing only in case are synonyms.

Use canonical exact polynomial normalization when applicable. For rational functions, compare only within declared domain restrictions and preserve exclusions: `(x²−1)/(x−1)` is not an unrestricted replacement for `x+1` when the original domain excludes x=1. Cross-multiplication alone must not accept an expression where denominators introduce or erase forbidden values. If the parser cannot prove equivalence within the supported domain, use an appropriate supported tool or clearly identified AI rubric review for ordinary practice, request clarification, or offer self-check. Do not claim exact symbolic proof from a few sampled numerical points or an unsupported model assertion. A new reviewed domain module can extend exact coverage independently.

<a id="sco-011"></a>

### SCO-011 — Symbolic processing must have bounded complexity

Proposed initial implementation limits: 256 lexical tokens, nesting depth 32, at most 16 declared symbols, integer exponents from −12 through 12, and a maximum of 2,048 expanded polynomial terms. These are resource limits for a local parser and must be configurable/versioned; they are not learner difficulty parameters. Stop safely at a limit and explain the supported notation without recording an incorrect conceptual answer. Never evaluate arbitrary Swift, JavaScript, Python, shell commands, or imported code.

Exact proof of trigonometric identities, arbitrary derivatives, matrix algebra, chemical formulas and proof equivalence requires appropriate supported tools or separate reviewed domain modules. AI may teach these topics and assess bounded explanation criteria with its method identified; it must not claim that the initial local parser verifies mathematics outside its scope. Do not advertise universal algebra equivalence based on the initial polynomial parser. Unit symbols have their own registry and case rules: metre `m` and a prefix/unit symbol `M` cannot be case-folded into the same token.

<a id="sco-012"></a>

### SCO-012 — Prose grading must preserve direction, conditions, and negation

For the arithmetic-mean objective, accepted concept coverage requires an additive total of the relevant observations and division by their count. “Sum observations / number of observations” passes. “Divide the count by the total” fails because direction is reversed. “Do not divide by the count” fails despite containing every keyword. “Add all values and divide by how many values there are; this works because each observation contributes once” passes. A response that includes the correct method and then asserts its negation cannot receive full credit.

A semantic AI rubric must define required concepts, relation direction, mandatory qualifiers, component weights, material contradictions and representative full/partial/incorrect examples. Examples calibrate the intended meaning; they are not an exhaustive accepted-string list. The grader must tie each credited or missed criterion to the learner's actual words and the task evidence. Keyword presence alone is insufficient, and a contradiction must affect the relevant criterion even if every expected keyword appears.

Evaluate the grading policy on held-out human-reviewed responses containing valid new paraphrases, terse and verbose answers, alternative correct reasoning, omissions, negations, changed quantifiers, mixed languages where supported and plausible unsupported claims. Check unsupported confidence, irrelevant fluency/style penalties and systematic disagreement. Compare capable local and cloud routes for the supported objectives and languages; an incapable local route must not grade simply because it is available. Route to a stronger evaluator, clarification or pending review when the policy requires it.

Provide **Review grade** for overlooked meaning or an apparently wrong criterion. The learner can request an explanation or reevaluation without changing their original response or confessing an error. The reviewed result records the contested criterion and reason for any change. Feedback from review informs rubric quality evaluation; it does not automatically endorse every requested score change. Treat instructions embedded inside an answer as answer content, not permission to alter the rubric or award points.

<a id="sco-013"></a>

### SCO-013 — Retrieval computations must use computational response contracts

The 800 computed retrieval instances should stop using exact prose strings as their primary arithmetic authority. Attach a typed quantity, formula, coordinate, sequence, or discrete result contract. The knowledge target remains the learned relationship being retrieved; a correct computed answer may provide evidence for applying that relationship, while a recognition answer must retain its weaker response-form identity. A binary numeral may include leading zeroes unless a fixed-width/minimal-width instruction says otherwise. A unit already fixed by the response control need not be retyped.

<a id="sco-014"></a>

### SCO-014 — Self-check remains an explicit alternative to AI grading

For supported short-response and recall tasks, offer AI rubric grading as the normal evaluation route. Self-check is available when the learner wants manual comparison or when suitable AI is unavailable; selecting it must be explicit. The learner must attempt recall before revealing the reference. The app then shows a checklist tied to that target, not generic criteria such as “names the central idea” for every question. EX-C06 on the median must distinguish ordering, odd count, and averaging the two central observations for an even count. “Matched,” “partly matched,” and “not yet” are self-reports; do not encode “matched” as an objectively correct response or include it in verified accuracy.

Store reveal time, whether a pre-reveal attempt occurred, checklist selections, the self-rating, and optional reflection. Do not require lengthy reflection on every successful recall. A closed-reference retry can be offered as a new linked attempt. It cannot overwrite the first response or convert an assisted attempt into unaided success. A rating made without attempting recall is a review exposure, not recall evidence. A later AI evaluation may inspect the original pre-reveal response as a separately linked grade; retain the actual assistance and timing sequence, and never rewrite a self-rating into an AI result. An unavailable grade may remain pending while the learner studies other material.

<a id="sco-015"></a>

### SCO-015 — Composite and state answers must grade typed components

Stop grading estimate/plausibility/exact tasks as opaque dictionaries of literal strings. Each response field has its own domain, accepted equivalents, mandatory/optional status, and weight. A whole accepted equivalent state receives full credit regardless of whether it matches the canonical spelling. A state task can use integer, rational, Boolean, enum, and declared identifier fields. Boolean text aliases such as `true` and `True` may be accepted under an explicit Boolean parser; source-code identifiers remain case-sensitive.

A composite answer may combine exact components with AI-rubric explanation components. Declare each component's evaluator and weights before response; an uncertain AI component remains pending/reviewable without discarding a valid exact subresult or presenting an incomplete whole answer as fully correct.

For EX-C08, starting at count 10 and ready false, execute `count -= 3`, set ready from `count <= 7`, then `count += 2` without recomputation. The final state is count 9, ready true; the invariant “ready equals count<=7” is violated. In a practice rubric assigning state 0.8 and invariant 0.2, both state fields correct plus the right invariant earns 1; both fields correct plus a wrong invariant earns 0.8. If state component weights differ, declare them. An accepted Boolean alias must not lower credit.

<a id="sco-016"></a>

### SCO-016 — Estimates and units require explicit semantic policies

Define `estimateMode` as one of nearest specified unit, nearest specified significant digit count, nearest power of ten, bounded practical estimate, or assumption-derived range. State the chosen task in learner language. For “nearest power of ten” of 198×48, 10,000 is the target. For “give a useful approximate product,” a reasonable declared range such as 9,000–11,000 may be chosen editorially for that task; it is not a scientifically universal tolerance and must be reviewed against the objective. Exact product 9,504 is not conceptually wrong merely because it is precise; the task may separately assess whether a preliminary estimate was recorded before exact work.

The plausibility control should represent a typed judgment such as plausible / too small / too large with an optional reason. It must compare the learner's own estimate and exact result under a defined rule, not always key “yes” independently of what they entered. If the estimate is 100 and the exact answer 9,504, “plausible” is not correct even though it is the canonical word in another generated item.

A quantity contract declares whether the unit is supplied by the control, must be chosen, may be freely equivalent, or must match a requested representation. Prefixes, dimensional conversions, and significant-figure requirements are separate objectives. Locale parsing must be deterministic and explained when separators are ambiguous; do not silently interpret `1,250` differently between the displayed problem and submission. A locked metres suffix and an accessible “answer in metres” label eliminate avoidable unit-entry friction for simple conversions.

<a id="sco-017"></a>

### SCO-017 — Claim/evidence tasks must encode support constraints

A claim may require one evidence item, all items in a necessary bundle, or any one of several sufficient bundles. Encode these explicitly rather than insisting on one arbitrary map. EX-C07: observed group means support the descriptive contrast; convenience assignment supports a warning about baseline comparability; neither supports “every individual benefits.” A statement that restates the claim is not independent evidence merely because it has a different ID.

Full credit requires every claim's support condition and no prohibited unsupported edge. Partial practice credit uses declared claim/component weights and deducts unsupported attachments, with floor zero; “attach everything everywhere” must never be fully correct. Contradictory evidence should be an available category where the task requires it, not forced into “supports” or “ignore.” Feedback must identify the actual missing relationship or scope violation. Unknown/deleted evidence IDs are invalid submissions, not evidence of reasoning failure.

<a id="sco-018"></a>

### SCO-018 — Feedback and replay must preserve the original result

The first feedback sentence must say what happened in ordinary language: “Correct — 46×19 is 874,” “Your estimate is reasonable; recheck the exact multiplication,” or “I could not interpret that formula; use `*` for multiplication.” It must not call every correct answer “Supported” or every mistake “Revisit the decisive step.” The next sentence explains the shortest useful reason. AI feedback should refer to the actual reasoning that earned or missed a criterion and offer a practical next step. Expandable detail may show alternatives, source citations and a worked solution; a contextual tutor lets the learner ask follow-up questions or request a different example. Generated feedback must remain consistent with exact component results and source evidence.

A diagnostic trace, second attempt or grade review adds a linked result. It cannot mutate the original answer or scoring version. A reviewed AI grade may become the effective result for subsequent learning under the correction policy, with the original result, revised result and change reason still inspectable. Correcting a bad question at release time requires a separately governed historical correction decision; the UI must not silently revise yesterday's evidence. The application/state chapter specifies the migration and correction records.

## 5. Content identity, versioning, and editorial governance

<a id="con-020"></a>

### CON-020 — Separate identity layers and exposure relationships

Use `objectiveID` for the thing being learned, `familyID` for the generating activity, and `structureID` for its substantive reasoning pattern. A `semanticProblemID` identifies one substantive problem with specific givens and an authoritative response relation. `semanticFingerprint` is a reproducible digest of its canonical semantic contract. `contractRevision` identifies a change to that authority. Display-instance IDs identify presentations and reservations, not new questions.

A translation, font, option order, animation, surface noun substitution, pseudocode display skin, newly generated UUID, or changed difficulty label does not create semantic novelty. A changed substantive given and answer can create a new problem instance, but it still shares its structure and objective. Rewording `46×19` as 46 sensors with 19 readings each does not create an unseen mathematical structure. The adaptation layer can distinguish instance exposure from structure exposure using these fields.

For retrieval, the knowledge target identity survives different response forms. A single fact seen in recognition and then recalled is one knowledge target with two differently qualified attempts. A new computed instance can have a distinct problem identity when its essential givens and required answer genuinely change; it still belongs to the same knowledge relationship and calculation structure. The bank must not count nine renderings as nine additional knowledge contracts.

<a id="con-021"></a>

### CON-021 — Version the smallest changed authority and the containing edition

A copy correction that preserves meaning and grading increments a presentation revision. A changed correct answer, accepted-equivalence set, domain restriction, substantive givens, or score rule increments contract revision and the edition's manifest. Changes to generator behavior or candidate admission increment the appropriate generator/bank version. A scoring-policy update increments scoring version even if item wording is unchanged. Historic attempts retain their original references.

A corrected typo must not erase exposure history or present a familiar item as new. A genuinely changed contract must record `supersedes` and its relationship to the old problem: copy-only, answer-authority correction, altered givens, or new structure. A quarantined item must not reappear under a fresh UUID. The state/migration chapter owns how these relationships project into installed ledgers; the content release must supply the mapping.

<a id="con-022"></a>

### CON-022 — The release manifest must cover the actual delivered bank

The current offline bank explicitly leaves signed inventory coverage unset. The replacement release must include the admitted item identities/fingerprints, knowledge-target records, family/structure quotas, response-contract versions, generator version, and content assets in the signed inventory or a reviewed signed exception with an explicit expiry/next-release obligation. A code-signed application alone does not satisfy a separately required content-manifest audit.

For the standardized bundled-bank lane, validation must verify that every reserved item resolves inside the installed approved edition and that no changed bank mapping reuses the same edition identity. Missing signature coverage cannot be “fixed” by setting a Boolean or bypassing a gate. The content release process must follow the repository's [ContentSigning.md](../ContentSigning.md), with signing authority outside ordinary runtime generation. Deployment and signing are separate authorized release actions, not part of writing this specification. This manifest requirement covers the declared standardized shipped inventory; it is not a gate that prevents ordinary runtime AI-generated or personal-source practice. Those tasks retain accepted question/rubric artifacts and evaluation provenance under CON-001/002 and SCO-002.

<a id="con-023"></a>

### CON-023 — Every family needs an editorial record and an independent reviewer

The record must include the primary objective, prerequisites, approved domains/fields, four band definitions, generator parameter partitions, invalid regions, independent oracle, alternate forms, assistance policy, misconception taxonomy, accepted and rejected examples, sources where factual support matters, and locale/asset support. For standardized families, the reviewer must inspect sampled rendered items as a learner would see them and inspect all critical boundary cases. For dynamic AI question creation, review the generation and grading policies, representative rendered outputs and held-out response evaluations; do not require a human to individually approve every learner-requested question before normal practice can begin. A reviewer cannot approve a family solely by reading the generator comments or running self-consistency tests.

Factual source records must support the particular claim made, not merely share the topic. Elementary mathematical identities may be independently proved in the review record. Domain-specific facts need an appropriate textbook, primary source, standard, or official reference. Record limitations and assumptions. Avoid questions whose correctness depends on unannounced jurisdiction, rapidly changing product behavior, or personal medical/financial advice in the default general bank.

<a id="con-024"></a>

### CON-024 — Editorial review must evaluate language as part of correctness

Every task must have one short primary question, a clearly labeled deliverable, necessary assumptions, and consistent terminology. Use “observed difference” when that is all the data support; “causal effect” only when the task actually addresses identification. Do not use “source-backed” for a generic bundled statement with no displayed source. Remove implementation language such as “the bounded internal AST is interpreted” from ordinary learner instructions.

English and Japanese releases require equivalent task demands and accepted response support. Translating a question but leaving only English prose answers is incomplete localization. Language difficulty must not unintentionally become a prerequisite for a numeric skill. Content reviewers must inspect line wraps, notation, units, accessible reading order, and whether symbols preserve meaning under localization. The interaction chapter specifies presentation details; the contract must provide accurate localized inputs.

<a id="con-025"></a>

### CON-025 — Authored and AI feedback must form a useful learning sequence

For each supported misconception or missed criterion, provide an explanation, one smallest corrective action and an optional worked solution. AI should tailor these to the actual response, offer an alternative explanation when the first one does not help, and generate a follow-up question that addresses the missed idea. Use available exact tools and source context to substantiate the explanation; an AI inference about the learner's mistake remains tentative when the response does not establish it. Follow-up practice should vary the essential feature that caused the error while keeping unrelated demands manageable. After correcting a unit-direction error, a second item may reverse the conversion direction rather than merely replace 1,250 with 2,500. After a counterexample error, ask the learner to check premise and conclusion independently, then provide a different universal statement.

A replay or explanation must be optional when the learner was confidently correct and the objective is fluency. Do not require repeated generic “what went wrong?” reflections for correct answers. A wrong response should not trigger a long conceptual lecture unrelated to the actual mistake. Explanations must not claim evidence of a misconception when the response is ambiguous or the parser could not interpret it.

<a id="con-026"></a>

### CON-026 — Metacognitive tasks must not masquerade as subject knowledge

Retrieval Cycle Builder and Confidence Calibration teach learning procedures and judgment. Their success is evidence for those objectives only. A cycle task associated with a chemistry target must include a chemistry retrieval/reconstruction component before it can supply target-specific knowledge evidence. Merely ordering “attempt, compare, locate, retry” is a distinct procedural task. Source-Filter Trace must require the actual supplied source, candidate claims, and filter behavior; a fixed pseudocode return of an obviously correct label is insufficient.

<a id="con-027"></a>

### CON-027 — Content incidents need a reproducible correction path

A learner can report “my answer should be accepted,” “more than one option is correct,” “question unclear,” “fact seems wrong,” or “something else.” Attach edition, semantic ID, contract revision, response/scoring version, locale, and seed. The report preview states which question, response, source context and grading details will accompany the report according to the configured reporting workflow. Grade review should already have the saved response and rubric available; ordinary in-app reevaluation must not require a separate privacy workflow for each criterion. Triage must distinguish input parsing, answer equivalence, key error, ambiguity, missing prerequisite, and feature mismatch.

Confirmed wrong-key or duplicate-answer incidents quarantine the affected contract or parameter region. Review the learner impact and corrected evidence through the state chapter's correction policy. The chapter does not authorize silently deleting past attempts or automatically awarding learning mastery. A quality dashboard must show incident rate with exposure denominator and item revision; raw report count alone overweights popular questions.

## 6. Genuine variety with feasible inventory and no replacement

<a id="con-014"></a>

### CON-014 — Balanced admission must precede balanced delivery

The current first-1,000-unique scan must be replaced by release-time inventory admission with explicit family/structure quotas. At least 1,000 eligible semantic contracts per lab remains the planned offline-bank floor. This inventory provides a dependable offline baseline; it is not the ceiling of the AI learning experience or a prerequisite for releasing useful AI tutoring, grading and generated practice. The system must prove that the inventory can meet the quotas before advertising balanced mixed practice. Reserving many unique numeric variants of one family cannot substitute for creating missing families.

The following are proposed **editorial targets for a new 1,000-item edition**, not statements about current inventory and not psychometrically validated optimal proportions. The exact values are chosen to prevent the observed 98–99% concentration while retaining every catalog family. The quotas must be versioned and inspectable.

| Lab | Proposed admission quotas, in current catalog order | Total | Additional constraint |
|---|---|---:|---|
| Mental Mathematics | 100 for each of its 10 families | 1,000 | At least four substantive structures per family; a structure's number-only variants cannot exceed half that family's quota. |
| Spatial Reasoning | 167 coordinate rotation, 167 object rotation, 167 cross-section, 167 top-view, 166 cube-net, 166 reflection | 1,000 | Different transformations/objects/sections must carry the quota; changing coordinates alone cannot fill object or projection families. |
| Quantitative Intuition | 125 for each of its 8 families | 1,000 | Different probability structures, assumptions, and interval targets required; no more than half of a family's quota from one structure. |
| Scientific Reasoning | 112 Claim–Evidence Bounds; 111 for each of the other 8 families | 1,000 | Every family needs genuine scenarios with substantive design/evidence differences. |
| Logic & Debugging | 112 State Trace; 111 for each of the other 8 families | 1,000 | State Trace cannot dominate by variable substitution; other families need independent claim/program structures. |
| Retrieval Practice | 100 Free Recall, 160 Precision Recall, 140 Cloze, 100 Teach It Back, 120 Recognition Audit, 20 Cycle Builder, 140 Equation Reconstruction, 100 Figure Interpretation, 20 Source-Filter Trace | 1,000 | These are delivery assignments to 1,000 unique target/problem contracts, not 1,000 additional formats; maintain 125 target contracts in each field. |
| Transfer Lab | 143 for its first 6 families; 142 Saturation Check | 1,000 | Each includes both successful transfer and informative limits where appropriate; no more than half a family from one source/target structure pair. |

“Four substantive structures” is a proposed editorial breadth target. It does not mean four renamed settings. For rapid recall, separate multiplication-table facts, division inverses, decimal place-value facts, and signed-number facts only if the activity's objective and prerequisites explicitly support them. If broadening would make an existing activity misleading, create a reviewed successor subfamily or rename the activity with migration mapping rather than expanding it silently.

<a id="con-015"></a>

### CON-015 — Quota feasibility must be checked as a finite assignment problem

A candidate supplies semantic ID, family eligibility, structure, field, band, and compatible renderings. Admit a set satisfying hard uniqueness, content validity, required assets/locales, and declared quotas. For retrieval, the same target may support more than one rendering but may occupy only one slot in the edition's target count. Use a deterministic bipartite matching/min-cost-flow step to assign targets to compatible rendering slots while respecting field totals. Store the resulting assignment in the manifest. Do not assume every field/format/band cross-product exists.

If capacity is insufficient, fail the new edition's admission with an exact deficit report: available valid unique items, required count, and missing compatible assets/structures. The shipping product may continue the last valid approved edition with its limitations described accurately, or release a smaller specifically named practice activity outside the 1,000-item mixed guarantee if the product specification explicitly permits that lane. It must not fabricate novelty, bypass a minimum count, or silently relax a advertised balanced-bank guarantee to make a release pass.

<a id="con-016"></a>

### CON-016 — Per-target novelty and per-rendering variety must be distinguished

A no-replacement retrieval epoch consumes a target/problem identity once, whichever compatible rendering is delivered. It cannot later count the same target as fresh because it changed from free recall to cloze. A deliberate spaced review is permitted in a separate review schedule and is labeled review; it does not reset the mixed bank's novelty cursor. An imported personal fact is not a new standardized item and cannot fill an offline release deficit.

Where a target has only one meaningful form, deliver that form. Where several exist, choose among the approved forms under the mode, assistance, and prerequisite rules, and record the actual form. If the release's rendering quota cannot be realized because only 40 targets contain meaningful equations, it cannot promise 140 Equation Reconstruction assignments until another 100 suitable contracts/assets are authored.

<a id="con-017"></a>

### CON-017 — Separate candidate order from the reservation of an adaptive item

Within each profile/lab/edition/lane, deterministically shuffle admitted unique IDs within family queues and build a balanced whole-epoch **candidate priority order** using nonempty queues, proportional deficit, and seeded tie-breaking. The order is a reproducible inventory recipe, not an immutable list of all questions in an adaptive session. Persist its version/hash and the positions that have actually been reserved/consumed. Eligibility-aware search may bypass ineligible positions without consuming them; a single monotonically advancing cursor is insufficient when bypassed items remain available.

Use two explicit reservation strategies. **Fixed block** quizzes reserve their exact complete form/sequence at accepted launch and retain the existing consumed-on-abandonment behavior. **Adaptive item** sessions reserve and consume exactly one concrete first item in the accepted-launch transaction, before it can be presented. After an answer, permitted override, or explicit replacement, the adaptation layer supplies the next demand request; the content layer selects one eligible unconsumed contract from the remaining inventory, and an atomic transaction reserves/consumes that exact identity before presentation. Each decision has a stable ordinal, reason, selected contract revision, requested/realized band and demand, and reservation ID. Repeated execution of the same decision cannot allocate a second item.

A committed reservation remains consumed even if the learner closes the session before seeing or answering it. Consumption is an inventory event, **not** proof of exposure or performance: record presentation separately when the item is actually displayed. Optional prewarming of at most two possible next candidates is advisory only; it creates no reservation, consumption, exposure, or evidence. Recheck eligibility and identity during the actual transaction. A band override discards advisory candidates and affects the next item. It never regenerates different content or changes difficulty under an already committed semantic identity. Explicitly replacing the current item leaves that reservation consumed, then commits a new exact contract and links the reason; it cannot resurrect the old slot.

Both strategies preserve hard no replacement: concurrent windows cannot commit the same available position; a committed abandoned item is not issued again in that epoch; a session-level exclusion set forbids repeats within the session even across an epoch boundary. The state chapter owns the consumed-position set, decision idempotency, and migration from cursor-only ledgers. The adaptation chapter owns permitted live band changes. A protected form may select only from its approved fixed form or preauthorized adaptive branches; reserving its capacity is not exposure, and the next committed branch/item remains frozen once issued.

Short-block balance is a **soft** target subject to prerequisites, requested band, protected-form rules, invalidations, and remaining unique capacity. A 10-item block cannot include all nine families equally; some eligible families may run out. The hard invariants are truth, eligibility, exact identity, and no replacement. Report the realized mix and any unmet demand so the UI can name the session accurately. A failed content item is consumed/quarantined, never scored against the learner, and replaced only through a new valid reservation.

<a id="con-018"></a>

### CON-018 — Exhaustion fallback must preserve the guarantee it actually has

When a selected narrow activity runs out of unseen valid items, provide an explicit continuation: generate further practice with AI when a capable route is available, end the activity, continue with a named related activity, or deliberately review previous items. AI continuation saves new accepted contracts and retains prior exposure relationships; it does not pretend to add signed inventory to the exhausted standardized-bank epoch. Do not silently broaden “Cube-Net Puzzle” into coordinate rotation while keeping the original activity title. A review continuation starts a clearly labeled review lane and does not claim unseen items. Its exposure relationship stays linked to the original identities.

For mixed practice, if a preferred family is exhausted but other eligible unseen items remain, select those and record the reason. If all remaining items fail prerequisites, offer the prerequisite route or a review; do not label advanced ineligible material as suitable. If the whole eligible bank is exhausted, show that the set is complete before beginning a new epoch. A new epoch may repeat identities after the boundary policy, but never within a single reserved quiz.

<a id="con-019"></a>

### CON-019 — Epoch boundaries must solve capacity before reserving

For a fixed quiz or adaptive session crossing an epoch, exclude every ID already committed within that session from the next epoch portion. Place the previous epoch's configured tail after other candidate IDs where feasible. For a fixed block, check that enough unique eligible IDs remain to fill the requested block before committing it. For adaptive mode, check capacity for the one requested next item after each demand change. If the requested unique eligible capacity is unavailable, state the unmet demand and offer an eligible next route, a shorter session, or a separate review; never silently lower the band or reuse an identity. Do not enter an unbounded retry loop, reuse a question under a fresh ID, or incorrectly promise a requested count.

Tests must cover a bank whose family queues have sharply unequal capacity, a narrow selected activity, a final partial epoch, a quiz longer than remaining eligible capacity, two simultaneous windows, abandonment before the first answer, invalidated items after reservation, a version upgrade, and a target with multiple renderings. Properties checked are set uniqueness, no duplicate within the quiz, stable reservation identity, truthful realized mix, and finite termination. Runtime family balance cannot be an unconditional assertion when eligibility makes it impossible.

## 7. Seven complete worked examples

These are proposed editorial fixtures with independent arithmetic/logic checks. They are not claims that the current app contains the interactions described. Fixture IDs must remain stable in tests even if learner-facing wording is refined.

### EX-C101 — Mental Mathematics: compensation with a diagnostic retry

**Family:** `mental.compensation`. **Objective:** compute an exact product using a nearby round multiplier and signed compensation. **Band:** B2 Developing. **Prerequisites:** distributivity, multiplication by 10/20, addition/subtraction. **Independent prompt:** “Compute 46×19. Enter the exact result.” Essential representation: `46×19` only. **Key:** 874, independently verified by long multiplication and `46×(20−1)=920−46`.

Accept `874`, `0874`, and an exact expression only if the numeric parser explicitly supports arithmetic expressions for this task; otherwise explain that the field expects the final number before commitment. `874.0` is equal. Reject 920 as omitted compensation, 966 as compensation in the wrong direction, and 864 as an arithmetic error without inventing a misconception unless the work reveals it. Use numeric exact full-credit grading. An optional practice scratchpad can collect “nearby product” and “compensation” but cannot be mandatory in a final-answer fluency mode.

After 920, feedback reads: “46×20 is 920. Because 19 is one less than 20, subtract one group of 46: 874.” A requested hint before answering says “19 is one away from a round number,” records assistance, and does not expose the result. A follow-up `37×21` tests the opposite compensation direction. B1 uses one-digit facts with an explicit decomposition; B3 requires choosing among nearby multipliers; B4 combines two compensations with a reasonableness check. Larger arbitrary integers alone do not establish a new strategy.

**Verification:** exact arithmetic oracle over parameter partitions; sign-of-compensation tests; equivalent numeric spellings; no solution in independent context; submitted error remains unchanged after replay. This fixture maps to SCO-005, CON-004, CON-011, and QA-F02.

### EX-C102 — Spatial Reasoning: a genuine three-dimensional rotation

**Family:** `spatial.object-rotation`. **Objective:** track face identity through a specified object rotation. **Band:** B2 Developing. **Prerequisites:** named axes, quarter-turns, face adjacency. Define a cube centered at the origin with A on +x, B on −x, C on +y, D on −y, E on +z, and F on −z. Essential figure: cube with these face labels, a +z axis arrow, and a 90° counterclockwise arrow **as viewed from +z looking toward the origin**. Prompt: “After this rotation, which labeled face points in the +y direction?”

**Key:** A. A +90° active rotation about +z maps the +x normal to +y. Options A, C, D, E are distinct face identities. D is a direction error, C is failure to rotate, and E confuses the fixed axis. Face identity and normals, not a pre-rendered answer image, supply the oracle. The accessible alternative describes initial face normals and the viewpoint without naming the rotated result.

In teaching mode, the user can drag the cube, reset to the canonical viewpoint, and step through the rotation. In independent mode, the allowed interaction must not reveal the target orientation by performing the exact requested transform automatically. A post-response replay animates the transform and highlights the source face. B3 composes rotations about different axes; B4 compares unfamiliar asymmetric solids with explicit orientation constraints. Every transformation must preserve lengths, adjacency, and proper-rotation handedness; a mirror image is not a rotation.

**Verification:** rotation matrix/orientation oracle; full set of cube orientations; reversal/viewpoint cases; equivalent options rejected; hidden labels do not leak via accessibility; visual depiction matches stated active rotation. Maps to CON-006, CON-010, SCO-006, QA-F12.

### EX-C103 — Quantitative Intuition: Bayes through counts

**Family:** `quantitative.bayes`. **Objective:** condition on all positive results rather than all cases. **Band:** B2 Developing. **Prerequisites:** proportions, percentages, two-way tables. Use a synthetic manufacturing setting, not individualized diagnostic advice. Prompt: “Among 1,000 components, 100 have a defect. A screen flags 80 of those 100 and also flags 90 of the 900 components without a defect. Of the flagged components, what percentage have a defect? Give one decimal place.”

**Key:** `100×80/(80+90)=800/17≈47.0588%`, rounded to 47.1%. Essential table: defective flagged 80, defective unflagged 20, nondefective flagged 90, nondefective unflagged 810. The answer field supplies `%`. Accept `47.1`; if the specified response is one decimal place, `47.0588` can trigger a pre-commit rounding clarification or a separately declared representation component, not an arbitrary wrong-value verdict. Do not accept 80%, 8%, or 10% as numerically equivalent.

After 80%, explain that 80/100 is the screen's hit rate among defective components, whereas the question asks about the flagged group of 170. A practice interaction highlights the conditioning group only after a hint request or answer. B1 uses a fully assembled count table; B3 derives counts from rates and a rare base rate; B4 compares two screening policies with explicit costs and uncertainty while preserving the same conditional-probability target.

**Verification:** all table cells nonnegative, totals reconcile, denominators nonzero, numeric rational key and rounding agree, no medical framing, and accessible table totals do not substitute the answer for the task. Maps to SCO-005, SCO-016, QA-F21.

### EX-C104 — Scientific Reasoning: separate interval geometry, inference, and causality

**Family:** `science.figure-uncertainty`. **Objective:** choose a conclusion matching the measured contrast, its stated analysis, and study design. **Band:** B3 Challenging. Prompt: “In an observational comparison, group A has mean 21 and group B mean 32. The separate 95% confidence intervals for the means are [16,26] and [25,39]. The report supplies a 95% confidence interval of [2,20] for the mean difference B−A, calculated under its stated comparison model. Participants chose their group. Which conclusion is supported?”

**Key:** “B has the higher observed mean. The supplied interval for B−A excludes zero under the reported analysis, but self-selection prevents this result alone from establishing a causal treatment effect.” Distinguish three components: observed difference 11; difference-interval interpretation; assignment limitation. The individual mean intervals overlap, yet the supplied difference interval excludes zero. The task explicitly avoids the shortcut that overlap means nonsignificance.

Distractors: “The means must be equal because their intervals overlap”; “The result proves every participant benefits from B”; “The interval for B−A means 95% of individual outcomes fall between 2 and 20.” Each has one documented inferential error. Do not assert the supplied intervals were calculated from an accompanying raw dataset unless a consistent dataset and method are actually supplied. A simpler B1 fixture asks only whether two stated intervals overlap, with no significance inference. A B2 fixture interprets a difference interval crossing zero without calling that proof of equality. A B4 fixture compares randomized and observational designs with missingness or model sensitivity supplied explicitly.

**Verification:** numerical contrast; overlap predicate independent of inferential key; interval type and estimand shown; one correct choice; causal qualifiers preserved in feedback and accessible summaries. Regression seed 8424208090942894707 must either be regenerated with coherent claims or removed with an identity correction record. Maps to CON-007, CON-008, SCO-006, QA-S02, QA-F28.

### EX-C105 — Logic & Debugging: inspect a real stale-state defect

**Family:** `logic.state-trace`. **Objective:** distinguish stored state from a recomputed predicate. **Band:** B2 Developing. Initial state: count=10, ready=false. Rule: ready must equal `(count<=7)` at the end of each completed update operation. Program: decrement count by 3; set ready to `(count<=7)`; increment count by 2 without updating ready. Prompt: “After the final operation, enter count and ready, then identify the violated end-state rule.”

**Key:** count=9, ready=true; readiness rule violated. The nonnegative-count rule is not violated. The program is run by the existing restricted interpreter using typed AST values. The visible code is rendered from that AST so Python-like, Swift-like, or neutral displays cannot disagree with the oracle. Clarify that the rule is checked after completed update operations; do not ambiguously claim it was first violated at a transient internal expression step.

Accept reviewed Boolean aliases without changing score. After a wrong `ready=false`, the trace replay shows that no assignment changed ready after it was set true; it does not rewrite the original response. A repair follow-up asks the learner to choose or construct a bounded patch and run it against empty/edge/typical states. B3 adds a branch where the stale state appears only for some inputs; B4 asks for the smallest counterexample or invariant-preserving patch across an explicitly finite domain.

**Verification:** independent interpreter execution; typed per-field grading; invariant timing; alternate display skins share semantics; solution absent before submission; correct equivalent states receive 1. Maps to SCO-015, CON-025, QA-S05, QA-F34.

### EX-C106 — Retrieval Practice: recall the median without wording traps

**Family:** `retrieval.precision-recall` or `retrieval.teach-back`, depending on the explicit response mode. **Objective:** retrieve the ordered-data median rule including the even-count case. **Band:** B2 Developing. Prompt: “How do you find the median of an ordered list when the number of values is odd, and when it is even?” Reference: “For an odd count, take the middle value. For an even count, average the two middle values.”

For a constrained structured precision response, use two fields with reviewed concepts: odd-count rule and even-count rule. Accept “middle observation” and “mean of the two central observations.” Reject “take the middle value in both cases.” For free-text teach-back, capture the response and use an AI rubric with two equal-weight criteria: the odd-count central observation and the even-count arithmetic mean of the two central observations. “For odd n take the central observation; for even n average the middle pair” receives full credit even if it is absent from every stored alias. “Take the central observation” earns 0.5 when it correctly covers only the odd case; “take the middle value in both cases” earns the odd-case component but misses the even case. A contradiction about the even-case averaging rule cannot receive that component's credit.

Feedback for the partial answer says: “You have the odd case. With an even count, average the two middle values; for [2,4,7,9], that is (4+7)/2 = 5.5.” The learner can ask why averaging is used, review a missed criterion, or answer a new example. The numeric follow-up uses an exact evaluator; the explanation uses the saved AI rubric. If suitable AI is unavailable, save the original response for later grading or let the learner explicitly compare it with the reference and record a self-rating. The model's unavailability does not make the response incorrect.

The same target can later be revisited using a concrete ordered list such as `[2,4,7,9]`, whose median is 5.5, but that item records its relationship to the same rule. Recognition options, if used, contain plausible competing methods: central pair mean, lower central value, higher central value, mean of all observations. A new rendering alone is not a new target. B3 mixes ordering and parity decisions; B4 asks which transformation preserves or changes a median with a counterexample. Those are different demand contracts tied to the relationship, not mere rephrasing.

**Verification:** odd/even finite datasets; AI acceptance of unseen correct paraphrases; partial components, reversed operations and contradictions; grade review and immutable replay; local/cloud/pending fallback; self-check distinction; recall before reference reveal; target identity retained across forms. Maps to SCO-009, SCO-012, SCO-014, CON-016, QA-F44.

### EX-C107 — Transfer Lab: identify where a familiar rate rule stops working

**Family:** `transfer.saturation` with a linked `transfer.rate` foundation. **Objective:** map accumulation structure and recheck a capacity constraint. **Band:** B3 Challenging. Source example: a printer produces 12 labels per minute for 5 minutes, giving 60 labels. Target: a reservoir begins empty, water enters at 12 litres per minute for 5 minutes, the reservoir holds 40 litres, and overflow is not retained. Prompt: “How much water is retained after 5 minutes, and which source assumption must change?”

**Key:** 40 litres retained; unconstrained accumulation/absence of a capacity limit does not hold. The inflow total is 60 litres and overflow is 20 litres. The deliverable is retained volume, not delivered volume. A two-component practice rubric grades the quantity with the exact evaluator and the constraint explanation semantically with AI; full credit requires both. Accept equivalent unit quantities only under the declared representation policy. Reject 60 litres retained and the explanation “the rate is different” because the supplied rate is unchanged.

The source and target are shown as paired structures with quantities and units. A practice slider can vary duration and capacity after the first answer, illustrating `retained=min(rate×time,capacity)` for this explicitly constant-rate, initially empty, overflow-discarded model. B1 maps rate and time with no capacity; B2 changes units; B3 introduces capacity; B4 includes a nonzero initial amount or piecewise rate with all assumptions stated. Successful practice is not automatically near-transfer evidence; the adaptation/assessment chapter decides eligibility from prior exposure and origin metadata.

**Verification:** zero duration, zero/positive capacity, exact-fill boundary, below/above capacity, unit cancellation, alternative expression equivalence, and familiarity/structure metadata. Maps to CON-020, SCO-015, SCO-017, QA-F58.

## 8. Family inventory interpretation and implementation boundary

<a id="con-028"></a>

### CON-028 — The matrix is the migration inventory, not a new count claim

The following 58 rows are the activities in the current [NFDefaultContentCatalog.swift](../../Sources/TrainingEngine/NFDefaultContentCatalog.swift), in catalog order. Activity IDs are stable migration keys. `v0` etc. identify the **current fallback variant selector**, not a count of unique questions, a difficulty level, or a newly specified generator. Current mechanism descriptions refer to [NFFallbackExerciseGenerator.swift](../../Sources/TrainingEngine/NFFallbackExerciseGenerator.swift). Proposed B1–B4 demands describe work that must be authored and implemented.

Every row is governed by CON-001 through CON-027 and the relevant response rules. In addition to the concrete mechanics below, each family should use contextual AI teaching and targeted follow-up where useful. Explanations and justifications use semantic rubric grading, while exact mathematical, geometric and interpreter results retain their appropriate evaluators. `QA-Fnn` is a mandatory family acceptance suite. The tests listed are minimum substantive cases, in addition to schema, localization, accessibility, identity, assistance, and general scoring tests. A standardized catalog activity must remain unavailable at a band until its contract, assets, suitable evaluator and review record exist. Dynamic AI practice may provide further goal- or source-specific work through its evaluated creation policy, with actual demand and origin recorded; it must not impersonate an admitted standardized form. The UI must not advertise B4 content by relabeling a B1 seed.

<a id="con-029"></a>

### CON-029 — Family expansion must preserve a coherent operation

A matrix's advanced demand may require new substructures and a versioned generator; it cannot simply be stamped onto the old variant. If the expansion materially changes the activity promise, review its name/summary and provide an identity migration. Keep previously learned simpler forms in the appropriate band. Do not require every learner to complete every band of every activity; adaptation owns that selection.

The new quota for a narrow family must not be filled using semantic aliases. For cube nets, there are only 11 free cube-net shapes; rotations and relabelings of an otherwise identical query cannot manufacture hundreds of independent structures. Broaden reviewed tasks to queries that genuinely change the information or required relation, such as face adjacency, multiple fold constraints, specified intermediate folds, or validating a proposed fold. Count exact finite capacity after canonicalizing symmetries and query roles. If the resulting family cannot supply its proposed quota, CON-015's deficit path applies: author more coherent task types, revise the future edition's declared quota through review, or postpone that balanced edition. The implementation must never claim the capacity exists merely because parameter strings differ.

## 9. All 58 existing families: mechanism, prerequisites, demand changes, tests

### Mental Mathematics — 10 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F01 — `mental.rapid-recall`, Rapid Recall (v0) | Numeric products with left 6–12 and right 7–12. | Integer multiplication; inverse division for later forms. | B1: one-digit facts with optional reconstruction. B2: mixed multiplication/division facts without method cues. B3: signed and decimal-place facts with explicit prerequisites. B4: select/justify a fast reconstruction for unfamiliar related facts; do not turn this into an endurance timer. | Exact fact oracle; inverse consistency; zero/sign/decimal boundaries; timing separated from accuracy; declared new substructures and same-fact exposure deduplication. |
| QA-F02 — `mental.compensation`, Compensation Lab (v1) | Two-digit number times 9, 11, 19, or 21. | Distributivity; round multiples. | B1: supplied nearby product. B2: choose add/subtract one group. B3: compare two useful nearby multipliers. B4: two-factor compensation with a bound check and independently checked intermediate steps. | Both compensation directions; near-round boundaries; no cue in independent context; EX-C101; exact answers and valid alternative strategies. |
| QA-F03 — `mental.representation-relay`, Representation Relay (v2) | Fraction to percent; mixed generator sometimes uses mg to g. | Fractions; decimal place value; percent meaning. | B1: halves/quarters/decimals. B2: nonunit fractions and percentages above 100. B3: recurring rational forms under stated exact/rounded policy. B4: identify inconsistent linked representations in a table. Keep unit conversion a separately declared substructure. | Exact rational equivalence; percent scale; units do not leak across substructures; equivalent fraction/decimal inputs; precision instruction matches scoring. |
| QA-F04 — `mental.scientific-notation`, Scientific Notation Repair (v3) | Normalize a two-digit coefficient by one decimal shift. | Powers of ten; coefficient interval. | B1: one shift with shown place value. B2: positive/negative exponents and several shifts. B3: repair calculations combining coefficients and exponents. B4: compare magnitudes and detect cancellation/rounding issues under stated precision. | Value-preserving normalization; coefficient bounds; zero policy; negative exponents; equivalent valid notation; difficulty request changes actual shifts/operations. |
| QA-F05 — `mental.missing-factor`, Missing Factor (v4) | Solve integer box×multiplier=product. | Multiplication/division. | B1: one inverse with fact-table numbers. B2: signed or decimal factors. B3: one unknown in a two-operation relation. B4: select the only solution satisfying a stated domain after inverse transformations. | Unique solution/domain; zero multiplier rejected or deliberately classified; rational answers; forward substitution independent oracle; no invalid divide step. |
| QA-F06 — `mental.error-detective`, Percent Error Detective (v5) | Select the valid trace for one percentage of a base. | Percent multiplier; meaning of whole. | B1: identify percent-to-decimal scale. B2: locate first error in an actual trace. B3: distinguish changed base in sequential discounts/increases. B4: audit a table with multiple plausible errors and repair only the first decisive one. | Every trace step evaluated; first-error location; percentage-base changes; correct trace may use a different valid method; partial explanations do not pass contradictions. |
| QA-F07 — `mental.calculation-chain`, Calculation Chain (v6) | Add, multiply, subtract with small integers. | Operation order; intermediate values. | B1: two visible steps. B2: three/four steps with optional scratchpad. B3: branches or inverse checks with rational values. B4: locate a wrong intermediate step in two competing traces while preserving dependency order. | Interpreter/exact oracle; negative/rational states; diagnostic retry leaves original score; visible versus recalled intermediate demand declared; no memory-span efficacy claim. |
| QA-F08 — `mental.estimate-first`, Estimate First (v7) | Fixed nearest-power estimate around 200×50 plus literal plausibility/exact fields. | Rounding; multiplication; scale comparison. | B1: nearest stated power of ten. B2: useful one/two-significant-digit estimate before exact product. B3: compare bounds for a multistep expression. B4: choose an estimation strategy appropriate to error tolerance and explain whether a result can be ruled out. | Estimate-mode tolerance; actual learner estimate/result plausibility relation; exact component separate; accepted aliases full credit; ambiguous “estimate” wording forbidden. |
| QA-F09 — `mental.tool-judgment`, Mental or Machine? (v8) | One repeated-conversion/audit-trail scenario with an obvious tool choice. | Precision, repetition, consequence, auditability. | B1: one salient constraint. B2: trade precision against repetition. B3: choose among mental estimate, calculator, spreadsheet, or code for a concrete workflow. B4: propose a verification plan for a consequential calculation with conflicting constraints. | Multiple defensible tools encoded or question narrowed; no blanket “code always wins”; actual costs/constraints stated; comparable distractor wording. |
| QA-F10 — `mental.strategy-duel`, Strategy Duel (v9) | Prefer round compensation or ×100÷4 over costly/incorrect options. | Distributivity; factors; equivalent methods. | B1: compare valid and invalid methods. B2: compare two valid methods for a stated mental-work criterion. B3: choose under different exactness/working-memory constraints. B4: construct and verify an alternative method, then compare explicit operation counts or burdens. | Do not mark a mathematically valid method numerically wrong; criterion for “efficient” stated; strategy and result scored separately; tie cases accepted. |

### Spatial Reasoning — 6 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F11 — `spatial.coordinate-rotation`, Coordinate Rotation (v0) | Always a 90° counterclockwise point rotation in the positive quadrant. | Coordinates; direction; origin. | B1: one quarter-turn with axes. B2: clockwise/counterclockwise across all quadrants. B3: 180°/270° and non-origin centers. B4: compose translations and rotations or infer an unknown transform from enough correspondences. | Seed-11 duplicate regression; axes/origin/symmetry points; distance preservation about center; active/passive convention; every option semantically unique. |
| QA-F12 — `spatial.object-rotation`, 3D Object Rotation (v1) | Rotate a single coordinate triple about z; no labeled-face object task. | 3D axes; face normals; viewpoint. | B1: one labeled cube quarter-turn with teaching replay. B2: EX-C102 active rotation from an explicit viewpoint. B3: sequential rotations about different axes. B4: unfamiliar asymmetric object orientations with occlusion and no mirror substitution. | Proper rotation oracle; handedness; fixed-axis normals; order noncommutativity; visual/accessible agreement; matched face labels rather than coordinate-only substitution. |
| QA-F13 — `spatial.cross-section`, Cross-Section Puzzle (v2) | Three elementary solid/parallel-or-central slice cases. | Solid geometry; plane intersection. | B1: axis-aligned cube/cylinder/sphere slices. B2: translated planes and noncentral sphere radius changes. B3: oblique planes with permitted shapes derived geometrically. B4: infer or reject a proposed slice under multiple position/orientation constraints. | Plane actually intersects solid; degeneracy/tangency distinguished; no “circle versus ellipse” ambiguity from inclusive definitions; independent geometry oracle; symmetry deduplication. |
| QA-F14 — `spatial.top-view`, Top-View Decoder (v3) | Select length and width of a rectangular block. | Orthographic projection; occupied positions. | B1: footprint of a block. B2: stepped assemblies with hidden height. B3: choose between assemblies sharing one projection using a second view. B4: reconstruct all feasible arrangements or identify underdetermination from supplied projections. | Real occupied-cell model; height does not incorrectly affect top footprint; occlusion; multiple valid reconstructions encoded; view orientation specified. |
| QA-F15 — `spatial.cube-net`, Cube-Net Puzzle (v4) | Opposite-to-A query on a validated net. | Face adjacency; folding; opposite normals. | B1: marked fold hints. B2: opposite-face query without hints. B3: adjacency/orientation relations after partial folds. B4: evaluate multiple face constraints or find an impossible proposed net/fold under explicit rules. | All 11 free net shapes; fold collision/normal oracle; query-role/symmetry canonicalization; actual finite capacity audit; invalid nets never shown as valid; no label-only novelty. |
| QA-F16 — `spatial.vector-reflection`, Vector Reflection (v5) | Reflect a positive coordinate pair across the y-axis. | Coordinates; components; mirror line. | B1: reflection across a coordinate axis. B2: arbitrary quadrants and translated axis-aligned lines. B3: reflect across y=x or y=−x with clear geometry. B4: distinguish rotation/reflection compositions using orientation and fixed points. | Axis/line fixed points; distance-to-line preservation; involution property; unique choices at symmetric coordinates; direction and units consistent. |

### Quantitative Intuition — 8 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F17 — `quantitative.proportion`, Observed Proportion (v0) | Part/whole percentage with one-decimal tolerance. | Part/whole; percent. | B1: explicit full denominator. B2: derive total from complementary counts. B3: distinguish conditional from overall denominators. B4: compare rates across differently sized groups without confusing counts with rates. | Totals/denominators; zero-total case excluded or declared undefined; rounding boundaries; fraction/percent distinction; denominator misconception feedback. |
| QA-F18 — `quantitative.fermi`, Fermi Estimate (v1) | All four factors and multiplication formula are supplied. | Multiplicative decomposition; units; plausible ranges. | B1: select correct factors from a list. B2: supply one justified missing factor range. B3: construct an explicit decomposition and range. B4: compare sensitivity and decide which additional measurement most reduces uncertainty. | Dimension cancellation; factor independence assumptions stated; equivalent decompositions accepted; interval propagation; plausible assumptions reviewed, not exact-word graded; no false single “true” estimate. |
| QA-F19 — `quantitative.unit-bridge`, Unit Bridge (v2) | mm→m, sometimes in estimate/plausibility/exact fields. | Metric prefixes; dimension preservation. | B1: one prefix conversion with fixed destination unit. B2: choose factor orientation. B3: squared/cubed units or compound rates. B4: reconcile mixed units in a multistep calculation and identify a dimensionally invalid model. | Exponent applies to conversion factor; affine temperature conversions handled separately; quantity versus representation policy; exact rational values; unit omission according to control mode. |
| QA-F20 — `quantitative.scaling`, Scaling Law (v3) | Direct/inverse/square relation with factor 2 or 3. | Proportionality; exponents. | B1: direct scaling. B2: distinguish direct/inverse. B3: power-law transformation from a stated exponent. B4: combine scale changes or identify insufficient data when proportionality is not given. | Law-specific oracle; nonzero domains; negative/fractional factor policy; no multiplication shortcut for inverse cases; unchanged metadata cannot represent harder content. |
| QA-F21 — `quantitative.bayes`, Base-Rate Bayes (v4) | Natural-frequency conditional probability in a narrow rate range. | Two-way tables; conditional denominators. | B1: supplied positive-result counts. B2: EX-C103 complete table. B3: reconstruct counts from base rate and screen rates. B4: compare policies or posterior conclusions with explicit loss/uncertainty constraints. | Reconciled cells; no zero conditional denominator; complements; rare-base-rate cases; exact-rational/rounding check; prior and conditional probabilities never conflated. |
| QA-F22 — `quantitative.expected-value`, Expected Value (v5) | Probability-weighted signed outcomes. | Probability totals; weighted sums. | B1: two gains. B2: gains/losses and stated costs. B3: several outcomes with conditional branches. B4: compare expected value against a stated risk or resource constraint without claiming expected value uniquely determines preference. | Probabilities sum to 1; costs not double-counted; signs; unreachable branches; alternate valid utility/risk choices when not specified; independent exact oracle. |
| QA-F23 — `quantitative.regression`, Regression Detective (v6) | Extreme first score and lower second score; fixed cautious interpretation. | Sampling variability; selection; causal limits. | B1: identify extreme-based selection. B2: distinguish noise from evidence of permanent change. B3: compare repeated measurements with/without extreme selection. B4: assess intervention claims with a control group and explicitly modeled variation. | Do not assert regression as the only cause; include improvements/declines and no-change cases; observed data support keyed claim; uncertainty and causal design kept separate. |
| QA-F24 — `quantitative.interval`, Interval Inspector (v7) | Generic “95% uncertainty interval” scope selection. | Estimates; interval endpoints; procedure. | B1: read endpoints for a named quantity. B2: distinguish population observation intervals from mean-estimate intervals. B3: interpret confidence versus credible intervals under supplied definitions. B4: compare decision thresholds using an interval for the actual contrast and stated model. | Interval type always explicit unless omission is the task; no overlap-significance shortcut; zero inclusion not equality; confidence not automatically parameter probability; source-backed wording review. |

### Scientific Reasoning — 9 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F25 — `science.claim-evidence`, Claim–Evidence Bounds (v0) | Changing means with the same descriptive/causal-limit evidence mapping. | Observation versus inference; study design. | B1: support one descriptive claim. B2: distinguish descriptive and causal evidence. B3: match multiple claims to sufficient evidence bundles. B4: identify conflicts and revise scope across a bounded report with alternative explanations. | Evidence is not a tautological restatement; alternative support bundles; treatment direction varies; no universal causal claim from means; actual design differences create variety. |
| QA-F26 — `science.confound`, Confound Hunter (v1) | Baseline ability explicitly causes exposure and outcome. | Directed causal graphs; temporal order. | B1: one clearly described common cause. B2: infer graph from a scenario. B3: distinguish confounder, mediator, and collider with supplied graph. B4: compare adjustment plans under a declared causal model. | Graph paths and node roles oracle; no association-only definition of confounder; temporal/domain assumptions supplied; do not imply indiscriminate adjustment is safe. |
| QA-F27 — `science.next-experiment`, Next Discriminating Experiment (v2) | One intervention-versus-drift scenario; context supplies the best experiment. | Hypotheses; predictions; controls. | B1: choose an observation with contrasting predictions. B2: choose independent manipulation/measurement. B3: compare realistic designs with partial strengths and costs. B4: choose a sequential experiment plan under explicit resource and identifiability constraints. | No pre-answer key in context; prediction matrix validated; rival options genuinely discriminate some cases; impossibility/insufficient-control case; no universal uniquely “best” without criterion. |
| QA-F28 — `science.figure-uncertainty`, Figure Uncertainty Audit (v3) | Variable means/raw values with sometimes contradictory overlap claims. | Means; interval types; design scope. | B1: verify displayed geometry. B2: identify what an interval estimates. B3: EX-C104 contrast interval plus design. B4: audit model assumptions, paired/independent comparison, and practical threshold separately. | All 266 current bad cases replaced/quarantined; data-summary agreement; touching/disjoint/overlap partitions; significance from specified analysis; no causal inference from interval geometry. |
| QA-F29 — `science.bias-repair`, Bias Repair (v4) | Select randomization, blinding, and replication over post-hoc exclusion. | Assignment/measurement/selection bias. | B1: match a safeguard to one threat. B2: repair a two-threat design. B3: choose feasible safeguards with explicit ethical/practical constraints. B4: identify residual limitations after a partial repair and avoid overclaiming identification. | Each safeguard targets the named threat; infeasible options not universally keyed; replication does not remove every bias; selecting all cannot earn full credit. |
| QA-F30 — `science.competing-predictions`, Competing Predictions (v5) | Generic preference for evidence expected by one rival. | Hypotheses; conditional predictions. | B1: match each model to a prediction. B2: select discriminating evidence from a table. B3: update relative support with a supplied likelihood model. B4: identify an observation that both models fail and propose a testable revision. | Explicit hypotheses/data; predictions computed; evidence compatible with both does not settle comparison; numeric update if used independently verified; no hindsight-only model rewrite. |
| QA-F31 — `science.reviewer`, Reviewer Mode (v6) | Fixed convenience-assignment and truncated-axis concerns. | Design, visualization, reproducibility. | B1: find one documented flaw in a short report. B2: separate strengths from flaws. B3: rank threats to a stated conclusion. B4: propose a minimal revision and explain what remains unresolved. | Real bounded report/figure; axis baseline context matters; transparency not marked as a flaw; severity criterion explicit; multiple defensible rankings accepted or avoided. |
| QA-F32 — `science.experiment-sequence`, Experiment Sequence (v7) | Order generic hypothesis/prediction/control/contrast steps under an experiment question. | Experimental dependencies; measurement timing. | B1: order one concrete protocol chain. B2: parallel preparation steps and control checks. B3: insert a missing safeguard at a valid dependency point. B4: repair a branching protocol that cannot identify its target effect. | Prompt asks the deliverable actually scored; DAG alternate orders; stateful timing dependencies; dangerous/unsupported real-world procedure content excluded from generic tasks. |
| QA-F33 — `science.paper-sprint`, Paper Sprint (v8) | A preferred reading order without an abstract. | Question/method/result/limitation distinction. | B1: identify fields in a short synthetic abstract. B2: extract numerical result and limitation. B3: separate authors' conclusion from supported claims. B4: compare two conflicting bounded abstracts and identify the missing methodological detail. | Actual abstract included; every keyed extraction supported by text; no source hallucination; alternative accurate wording; reading strategy not misgraded as the only valid order. |

### Logic & Debugging — 9 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F34 — `logic.state-trace`, State Trace (v0) | Many numbers in one stale-derived-state program. | Assignment; Boolean conditions; invariants. | B1: two assignments. B2: EX-C105 stale state. B3: conditional updates with different branch outcomes. B4: find a smallest counterexample or compare invariant-preserving updates across a finite state space. | Independent AST execution; invariant timing; branches cover both paths; typed aliases full credit; display skins no new semantics; actual program structures required for quota. |
| QA-F35 — `logic.conditions`, Necessary or Sufficient? (v1) | Divisibility by 4 versus evenness, with explanation before answer. | Implication; converse; counterexample. | B1: supplied small truth/set examples. B2: classify necessary/sufficient/both/neither. B3: compound predicates with explicit domains. B4: construct a minimal counterexample to one direction or derive a weakest sufficient condition in a bounded domain. | All four relation categories represented; vacuous truth/domain restrictions reviewed; no answer in context; truth-table/set oracle; alternative valid counterexamples. |
| QA-F36 — `logic.counterexample`, Counterexample Quest (v2) | Fixed even-product claim and visible 2×3=6 solution. | Premise; conclusion; universal quantifier. | B1: select a premise-true/conclusion-false case. B2: construct one in a bounded domain. B3: distinguish counterexample from a case outside domain. B4: find a minimal counterexample under an explicit order or repair the quantifier/condition. | Premise true and conclusion false independently checked; zero/negative domain cases; minimality oracle; no visible keyed example; multiple correct constructions accepted. |
| QA-F37 — `logic.proof-builder`, Proof Builder (v3) | One four-step parity proof. | Definitions; algebra; dependency. | B1: strict short proof chain. B2: alternate independent derivation branches. B3: supply a missing justified step. B4: choose sufficient lemmas and assemble a dependency-valid proof with an explicit target and domain. | DAG all topological orders; no cyclic proof; each inference locally valid; irrelevant lemma penalties declared; prose reasoning can receive AI criterion feedback and grading; unsupported proof is not labeled formally verified; explicit self-check remains an alternative. |
| QA-F38 — `logic.invalid-step`, First Invalid Step (v4) | Division-by-zero fallacy with divisor-zero cue. | Algebra operation preconditions. | B1: explicit single invalid operation. B2: locate first invalid line in a trace. B3: distinguish valid cancellation from domain loss. B4: compare two purported proofs with conditional validity and repair the earliest unsupported step. | Nonzero and zero branches; prior lines verified; first versus any invalid step differentiated; domain preservation; solution removed from independent preamble. |
| QA-F39 — `logic.boundary-bug`, Boundary Bug Hunt (v5) | One loop always misses last element. | Index ranges; empty/singleton cases. | B1: trace singleton boundary. B2: choose minimal failing input. B3: bugs dependent on value as well as size. B4: shrink a counterexample across a finite structured input domain under a declared minimization order. | Empty/singleton/typical input execution; expected output defined, including zero-valued elements; minimality criterion; no test input outside declared domain; interpreter bounds. |
| QA-F40 — `logic.complexity`, Complexity Duel (v6) | Linear scan versus ordered pair enumeration. | Input size; operation counts. | B1: count concrete loop iterations. B2: infer linear/quadratic growth. B3: triangular, logarithmic, or composed loops with stated primitive costs. B4: compare asymptotic growth with finite-size constants and an explicit workload. | Correct dominant term; loop bounds inclusive/exclusive; early exits and input assumptions; output-size misconception; do not equate asymptotic class with fastest at every n. |
| QA-F41 — `logic.loop-repair`, Loop Repair (v7) | Choose index<count instead of count−1. | Loop invariant; bounds; exact-once visitation. | B1: choose a safe bound. B2: repair start/bound/increment combinations. B3: preserve a data-dependent invariant across branches. B4: choose a minimal patch satisfying a reviewed test domain and explain a remaining limitation. | Empty/singleton/multi-element tests; no duplicate/omitted visits; patch authority from interpreter; hidden tests meaningful rather than mirrored implementation; unsafe text never executed. |
| QA-F42 — `logic.calibration`, Confidence Calibration (v8) | Pick 70/80/90% with small-sample caution. | Frequencies; probability; uncertainty. | B1: compare stated confidence to an observed rate. B2: identify over/underconfidence in a supplied table. B3: compare groups with different sample sizes/uncertainty. B4: diagnose confidence changes under selection or shifting task mix using explicit data. | No individual certainty inferred from 10 answers; comparable population stated; proper separation of evidence and preference; no always-50% strategy; adaptation calibration model remains separate. |

### Retrieval Practice — 9 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F43 — `retrieval.free-recall`, Free Recall (v0) | Self-check with three generic criteria. | Prior exposure to a specific target. | B1: recall a short fact after learning. B2: recall a relationship and condition. B3: recall several linked elements without source cues. B4: reconstruct an explanation including a limitation, assessed by a source-supported AI rubric. | Attempt-before-reveal; semantic concept/condition/contradiction grading; unseen paraphrase acceptance; local/cloud/pending paths; target-specific self-check alternative; no 100% accuracy from “matched”; source/target identity and assistance provenance. |
| QA-F44 — `retrieval.precision-recall`, Precision Recall (v1) | Exact-string short answer for any fact/computation. | Relevant target knowledge; supported answer notation. | B1: constrained name/value. B2: EX-C106 odd/even relationship fields. B3: a formula/application with conditions. B4: distinguish closely related definitions using a required qualifier and a reviewed constrained response. | Arithmetic-mean paraphrase; `2*x`/`4x`; case-sensitive F/f; label versus formula domain; unit-fixed numeric answers; AI grades explanatory prose beyond aliases; unavailable or uncertain grading remains pending/reviewable. |
| QA-F45 — `retrieval.cloze`, Relationship Cloze (v2) | Full question prefixed “Cloze reconstruction.” | Learned relationship; context comprehension. | B1: one meaningful blank. B2: choose the omitted relation or condition. B3: multiple linked slots with unambiguous scope. B4: reconstruct a omitted causal/mathematical dependency from a bounded source excerpt. | Actual omission; no multiple unconstrained completions; slot grammar/units; answer not elsewhere in excerpt; changed rendering retains target identity. |
| QA-F46 — `retrieval.teach-back`, Teach It Back (v3) | Self-check explanation with generic criteria. | Learned entities, relationship, conditions. | B1: explain one relation simply. B2: include a necessary condition. B3: use a concrete example and counterexample. B4: explain the boundary of applicability to a peer in a bounded scenario. | AI rubric evaluates concepts, relations, examples and boundaries; valid alternative explanations accepted; unsupported added scope affects its criterion; no arbitrary essay-length penalty; grade review and explicit self-check alternative; original response and feedback preserved. |
| QA-F47 — `retrieval.recognition`, Recognition Audit (v4) | One canonical answer versus generic relationship statements. | Target familiarity or source reading. | B1: distinguish plausible neighboring concepts. B2: choose correct direction/condition. B3: discriminate near-miss statements differing in one qualifier. B4: select a supported reconstruction from a bounded source with misleading but plausible alternatives. | Comparable option grammar/length; target-specific misconception distractors; unique supported interpretation; no recognition-as-free-recall claim; source shown only when mode permits. |
| QA-F48 — `retrieval.repair-cycle`, Retrieval Cycle Builder (v5) | Fixed workflow order unrelated to each target. | Attempt/review distinction; target knowledge if assessed. | B1: learn the explicit recall-review cycle as metacognitive practice. B2: locate a specific mismatch in a supplied attempt. B3: choose a targeted repair and make a closed-reference retry. B4: distinguish incomplete recall from an invalid source claim and plan the relevant follow-up. | Generic workflow cannot count as target knowledge; actual discrepancy exists; retry is new linked attempt; valid workflow orders encoded; reference hidden again before retry. |
| QA-F49 — `retrieval.equation`, Equation Reconstruction (v6) | Generic E_source+C_stated→blank plus exact prose answer. | Specific formula and symbol meanings. | B1: fill one term/coefficient. B2: reconstruct one side with units. B3: restore missing dependency/condition. B4: rebuild a reviewed derivation fragment while preserving domain and variable roles. | Real target equation; F/f and function/multiplication distinction; restricted equivalence; domain exclusions; missing required asset disables form rather than generating generic equation. |
| QA-F50 — `retrieval.figure`, Figure Interpretation (v7) | Two-row table repeats the question. | Reading the actual figure type. | B1: read a plotted value/label. B2: recover a supported trend. B3: relate a figure to the target equation or condition. B4: distinguish two plausible interpretations using uncertainty/design information explicitly supplied. | Actual chart/table data required; axes/units/legend; accessible equivalent; claim bounded by data; no statistical shortcuts; paraphrase or structured response appropriate to task. |
| QA-F51 — `retrieval.source-filter`, Source-Filter Trace (v8) | Fixed pseudocode returns an obvious supported candidate. | Source claims; Boolean filters; bounded trace. | B1: evaluate one claim against explicit source evidence. B2: trace changing candidate order and support states. B3: handle multiple supported/unsupported qualifiers. B4: repair a filter whose logic accepts an unsupported scope expansion. | Actual source support relation; varied return position/no-result case; interpreter oracle; content evidence distinct from code-trace evidence; no opaque generic “supported” label answer cue. |

### Transfer Lab — 7 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F52 — `transfer.sequence`, Transfer Sequence (v0) | Generic identify/represent/solve/check order. | Familiar source method; target comprehension. | B1: map named source quantities. B2: order actual target-specific steps. B3: insert a needed assumption check before a risky transfer. B4: revise a partially valid plan where source and target dependencies differ. | Real source/target pair; dependency-valid alternatives; transfer process distinct from target solution; no generic order counted as quantitative mastery. |
| QA-F53 — `transfer.conditions`, Preserve Transfer Conditions (v1) | Fixed select structure preservation and constraint recheck. | Assumptions; units; mathematical roles. | B1: identify same/different units. B2: classify preserved versus changed assumptions. B3: determine whether a method remains applicable after one constraint changes. B4: identify the minimal additional information required to justify transfer. | Every condition explicit; alternative sufficient bundles; cannot copy coefficients across units; insufficient-information answer where appropriate; no always-choose-cautious pattern. |
| QA-F54 — `transfer.rate`, Rate in a New Field (v2) | Rate×time with only number/context changes; 986 bank slots. | Constant rates; accumulation; units. | B1: identify rate/time in a new setting. B2: convert units before accumulation. B3: piecewise constant rates or nonzero initial quantity. B4: distinguish input flow, retained amount, and outflow under a supplied conservation model. | Quantity target explicit; constant-rate assumption checked; piecewise exact integration; zero/time/unit boundaries; source/target structure metadata; strict bank family quota. |
| QA-F55 — `transfer.representation`, Table-to-Equation (v3) | Four simple y=kx tables. | Ratios; linear relations. | B1: direct proportionality table. B2: affine relation with intercept. B3: discriminate inverse/quadratic/linear forms from sufficient data. B4: identify underdetermination or select among a stated finite model class with noise/measurement assumptions. | Enough data for uniqueness within declared model class; do not imply finite points identify a universal function; every row verified; equivalent equations accepted; ratio versus difference errors. |
| QA-F56 — `transfer.causal-map`, Causal Structure Map (v4) | Fixed controller/regulation feedback evidence mapping. | Directed graphs; feedback; delays. | B1: map node roles. B2: map direction and sign of edges. B3: compare delayed feedback structures across unfamiliar labels. B4: identify why an apparent analogy fails when an edge, delay, or external input differs. | Graph isomorphism under permitted role mapping; direction/sign/delay preserved; surface labels insufficient; multiple valid maps encoded; no metaphor-only claim of causal identity. |
| QA-F57 — `transfer.interacting-variables`, Interacting-Variable Ratio (v5) | Double numerator and halve denominator, six baseline values. | Ratios; multiplicative changes. | B1: change one quantity. B2: simultaneous opposing changes. B3: map ratio roles across concentration/density/rate contexts with units. B4: infer a missing factor or identify when a denominator change violates a constant-quantity assumption. | Nonzero denominator/domain; independent factor transformation; exact rational oracle; realistic conservation assumptions explicit; alternative units; varied transformations beyond always ×4. |
| QA-F58 — `transfer.saturation`, Saturation Check (v6) | One generic “check linearity” answer. | Linear accumulation; capacity/limits. | B1: identify a stated cap. B2: decide whether source linear rule applies within range. B3: EX-C107 retained versus delivered amount. B4: piecewise behavior with initial state, threshold, or multiple constraints explicitly supplied. | Exact threshold equality; below/above cap; no unsupported universal linearity; retained/delivered distinction; boundary assumptions; transfer evidence only with eligible origin/exposure metadata. |

## 10. Verification, implementation order, and completion gates

<a id="sco-019"></a>

### SCO-019 — The score test corpus must contain both meaning-preserving and meaning-changing edits

Every authoritative answer needs tests that mutate one meaningful feature at a time: reverse a relation, negate it, alter a quantifier, remove a condition, change a sign, change an exponent, change a unit prefix, swap F/f, insert redundant parentheses, add insignificant zeroes, or use a declared synonym. The correct acceptance boundary must be decided editorially before implementation. Tests must include invalid combinations that contain all expected keywords. A catalog audit that submits only each stored canonical key back to the same scorer is not adequate.

| Acceptance suite | Inputs / execution | Required corrected result | Evidence mapping |
|---|---|---|---|
| QA-S01 | Spatial seed 11; enumerate all generated option semantic values; symmetry/axis/origin partitions | Exactly one semantic correct choice and no equivalent distractor; any shipped invalid old contract is handled as an item error | QA-C01; CON-006; SCO-006 |
| QA-S02 | Entire bounded uncertainty parameter domain; original science seed; touching/disjoint/overlap fixtures; individual versus difference intervals | Stimulus/narrative agree; every key follows the declared estimand and procedure; overlap flag does not determine inferential significance | QA-C02; CON-007; EX-C104 |
| QA-S03 | Arithmetic-mean paraphrase; `2*x` for x² derivative; `4x` for 2x² derivative; relation reversal and negation | Equivalent answers receive 1; reversed/contradictory answers do not; unseen valid prose is graded by the semantic AI rubric; uncertainty/service failure is not a wrong answer | QA-C03; SCO-009–SCO-013 |
| QA-S04 | F(b)−F(a), f(b)−f(a), F*b−F*a, swapped endpoint order, valid grouping variants under F′=f | Only domain-valid antiderivative expression/equivalents receive full credit; roles/case retained | QA-C04; SCO-010–SCO-011 |
| QA-S05 | Canonical estimate/state; every declared equivalent spelling; combinations of field alternatives; one wrong field | Every fully accepted equivalent yields correct/1; partial states have declared component scores and false correctness | QA-C05; SCO-001; SCO-015 |
| QA-S06 | Every family and protected purpose; inspect visual/accessibility pre-answer role graph | Only essential givens are exposed; no keyed counterexample, zero-divisor conclusion, or best-experiment solution before response | QA-C08; CON-004; CON-008 |
| QA-S07 | Numeric exact/rounded/estimate policies, fraction/decimal/scientific notation, locale separators, fixed/free units, zero denominator | Meaning-preserving notation accepted under declared mode; ambiguity clarified; invalid mathematical values rejected safely | SCO-003; SCO-005; SCO-016 |
| QA-S08 | Multiple-choice and claim/evidence correct sets, missing edge, extraneous edge, select-all, alternate sufficient bundles | Full correctness only for complete valid support/set; selecting everything cannot exploit partial credit | SCO-007; SCO-017 |
| QA-S09 | Ordering DAG with independent steps; missing/repeated node; reversed edge; authored cycle | All valid complete topological orders accepted; invalid order rejected; cyclic authored contract blocked | SCO-008 |
| QA-S10 | Free recall with/without pre-reveal attempt; all three self-ratings; closed-reference retry | Self-reported outcome distinct from verified accuracy; retry linked and original intact | SCO-014; CON-026 |
| QA-S11 | Same contract/response across option order, display skin, theme, offline/online state, supported locale representations | Exact evaluator outcome is invariant; accepted AI grade replays unchanged without rerunning the model; explicit reevaluation is a linked grade revision; localized interpretation policy remains explicit | SCO-002; SCO-003 |
| QA-S12 | Unsupported symbolic grammar, resource limits, overflow, malformed tuple, stale option/evidence ID | Finite safe response with explanatory invalid/clarification outcome; no crash, code execution, or false conceptual score | SCO-003; SCO-011 |
| QA-S13 | Held-out human-reviewed short responses: new paraphrases, omissions, negations, contradictions, valid alternative reasoning, terse/verbose English and Japanese | AI criterion results match the reviewed rubric to a declared and evaluated quality threshold; disagreement is inspected; style alone does not change subject credit | SCO-009; SCO-012; CON-024 |
| QA-S14 | Local/cloud AI routes, timeout, offline response, cancellation, late reply, interrupted save, relaunch, duplicate retry | Original response and pending grade survive; only the intended response receives one accepted result; no unavailable-service wrong score; saved feedback remains available offline | SCO-001–002; SCO-014; SCO-018 |
| QA-S15 | Challenge an overlooked criterion, request reevaluation, then complete a new retry | Original response and grade remain readable; reviewed change has a reason and one effective result; new retry is linked; downstream ordinary learning uses the qualified effective grade | SCO-002; SCO-012; SCO-018 |
| QA-S16 | Generate from a goal and selected source; inspect cited support, rubric, exact subresults and targeted follow-up | Coherent task and rubric are saved before response; citations support claimed source facts; AI explanation agrees with exact subresults; follow-up addresses the actual learning need | CON-001–005; CON-025 |

<a id="con-030"></a>

### CON-030 — Bank and identity tests must validate capacity, not only counts

| Acceptance suite | Required scenario | Invariant |
|---|---|---|
| QA-B01 | Full new edition admission for every lab | At least required unique semantic capacity; approved quotas and all mandatory assets; deficits fail before release. |
| QA-B02 | Whole epoch from heavily unequal family queues; all permutations audited | Every admitted semantic ID appears exactly once; deterministic order; realized mix matches finite admitted inventory. |
| QA-B03 | Two concurrent windows, abandon-before-answer, relaunch | No reservation collision or reuse; quit does not reset novelty. |
| QA-B04 | Quiz crosses epoch with prior-tail and within-quiz exclusions | No duplicate inside the quiz; finite fallback when requested unique eligible capacity is unavailable. |
| QA-B05 | One target supports free recall, cloze, recognition; translations and option shuffles | Rendering/locale changes do not add target novelty or erase exposure. |
| QA-B06 | Selected family exhausted; remaining lab items fail prerequisites; review chosen | No silent activity substitution, fake novel ID, or forced ineligible item; truthful named continuation. |
| QA-B07 | Copy-only revision, answer correction, generator change, quarantined item | Correct identity/supersession relation; required edition/scoring versions; installed historical attempts retain references. |
| QA-B08 | Retrieval field totals plus compatible rendering slots deliberately infeasible | Assignment algorithm returns exact deficit; it does not count one target twice or attach meaningless assets. |
| QA-B09 | Current-bank comparison audit | Report concentration by family **and structure**, distinct targets, rendering mix, band capacity, and duplicate/invalid counts; raw 1,000 count alone cannot pass. |

<a id="con-031"></a>

### CON-031 — Release review must inspect representative learner sessions

For the complete proposed four-band release, after automated contract checks reviewers must complete at least one Foundation, Developing, Challenging, and Advanced session in each lab using the actual renderer and response controls. This is 28 editorial sample sessions, chosen for band and family coverage rather than a claim of statistical validation. An interim corrective release reviews every advertised lab/band combination; it must not advertise unimplemented bands merely to satisfy a 28-session count. Include a keyboard-only and accessible reading pass for every response/representation type. Also complete AI-created general and source-driven sessions with short-response grading, contextual tutor questions, grade review, a supported local route and interrupted cloud/offline fallback. Human review must assess the usefulness and correctness of actual AI outputs, not merely the existence of a prompt template. The interaction chapter defines device sizes and assistive-technology coverage.

For each sample, reviewers answer: can a learner identify the deliverable; are prerequisites and assumptions sufficient; is the task materially different at its band; can ordinary valid notation be entered; does a correct answer receive full credit; do wrong alternatives expose real misconceptions; can the explanation be followed; does the session feel varied without becoming incoherent? Record any content wording that requires reading implementation terminology. A nontechnical/editorial reviewer must inspect at least the instructions and feedback, not only an engineer familiar with internal schemas.

<a id="con-032"></a>

### CON-032 — Instrument quality without inventing a psychometric model

Record counts of presented/answered/skipped items, parse clarifications, grading disagreements, selected distractors, hints and tutor assistance, exact and AI-rubric outcomes, pending/failed evaluations, reviewed grade changes, self-check outcomes, and qualified timing. Include capability route, supported language/objective, completion latency and fallback success in AI quality evaluation; report observed performance rather than claiming all models grade equally well. Aggregate by edition/revision, objective, family, structure, response form, band, assistance, and language. The adaptation chapter determines which events are eligible for learner estimation. This chapter requires the underlying distinctions so an easy recognition item is not merged blindly with an uncued explanation.

Use low participation in a distractor, unusually high abandonment, or repeated parser clarification as review signals, not automatic proof of bad content. Compare rates only with denominators and relevant uncertainty; do not set unsupported universal pass-rate targets. The study record must retain the original response, rubric, supporting context, accepted grade and reviewed revisions needed to understand a questionable result. Diagnostic summaries can reference that record without copying entire sources; offline replay must not require an external grading service.

<a id="con-033"></a>

### CON-033 — Implement in a dependency order that cannot hide unresolved defects

| Work package | Concrete deliverable | Depends on | Completion condition |
|---|---|---|---|
| C-A: trust repairs | Duplicate-option guard; coherent interval authority; accepted-state full-credit fix; independent-mode scaffold roles | Existing generator/scorer adapters | QA-S01, S02, S05, S06 pass on corrected behavior; known defective regions quarantined or replaced with version mapping. |
| C-B: AI grading and exact evaluation | Semantic short-response AI rubric grading; domain-specific exact parsing; combined criteria; grade review; pending/retry/offline outcomes; explicit self-check alternative | Shared state/outcome and AI service contracts | QA-S03, S04, S07–S15 pass; valid paraphrases receive useful grades; accepted AI results support normal learning and durable replay. |
| C-C: editorial schema | Objective/family/structure identities; four-band demand records; reviewer/oracle records; compatible-rendering assets | C-A and shared adaptation fields | All 58 matrix rows have reviewed B1/B2 coverage; unsupported B3/B4 availability remains explicit, never relabeled. |
| C-D: AI creation and genuine family expansion | Goal- and source-driven question creation, contextual tutoring and targeted follow-ups; new scenario/program/geometry/target structures for the offline bank | C-B; evaluated generation policies; C-C for standardized inventory | QA-S16 and AI quality/journey checks pass; separately, finite candidate pools satisfy approved edition quotas and QA-F01–F58 for admitted bands. |
| C-E: bank admission and rotation | Deterministic capacity assignment; approved balanced inventory; whole-epoch permutation; exhaustion fallback | C-C, C-D, atomic reservation integration | QA-B01–B09 pass; current first-unique concentration cannot recur unnoticed. |
| C-F: release and evaluation | Signed edition inventory, incident workflow, 28 editorial sample sessions, quality metrics | C-A through C-E, external release authority | Manifest covers delivered content; all admitted contracts reproducible; outcomes match rendering; unresolved content limitations documented. |

C-A can ship as a corrective edition before the entire expanded bank is ready, provided its identity corrections and honest inventory limitations are preserved. It must not claim all planned bands or balanced quotas have been delivered. The AI features in C-B/C-D are central release work and can be delivered before the full standardized-bank expansion, with capability and quality scope stated accurately. The offline-inventory portion of C-D cannot be replaced by widening integer ranges to hit a count. C-F is not complete when a checklist exists; it requires execution evidence.

<a id="con-034"></a>

### CON-034 — The chapter is complete only when quality and honesty agree

The intended content release is accepted when AI generation, contextual teaching and short-response grading work as normal learning features; qualified AI grades support progression; grade review and offline/pending recovery preserve saved work; every delivered item has a valid contract and appropriate evaluator; every fully accepted equivalent receives full credit; no protected item reveals its solution beforehand; all advertised forms and bands have real assets/demands; declared bank quotas are feasible and satisfied; no-replacement behavior is preserved across realistic failures; and ordinary learner feedback accurately describes the work assessed. Release notes must distinguish repaired grading from new content and new content from demonstrated learning outcomes.

Unresolved expert review, unavailable advanced families, exact-parser scope limits and specific AI capability/quality gaps must be stated clearly and routed to useful alternatives. These are concrete limitations to evaluate and improve, not a blanket policy that all open responses stay ungraded or all AI output is merely a suggestion. They are not reasons to invent correct answers, fake variety, conceal a scorer limitation, or label the same basic task harder.

## 11. Source and implementation reference map

| Repository source | Role in current implementation | Specification responsibility |
|---|---|---|
| [NFDefaultContentCatalog.swift](../../Sources/TrainingEngine/NFDefaultContentCatalog.swift) | 58 activities, stable IDs, fallback selectors, summaries, initial difficulty metadata | CON-028/029 and QA-F01–F58 inventory. |
| [NFFallbackExerciseGenerator.swift](../../Sources/TrainingEngine/NFFallbackExerciseGenerator.swift) | Actual seven-lab question drafts, parameters, strategies, renderings, answer schemas | CON-001–013 and the worked fixtures. |
| [NFExerciseModels.swift](../../Sources/TrainingEngine/NFExerciseModels.swift) | Eight interaction cases and current exercise/scoring-related metadata | CON-001, SCO-001–018 migration adapters. |
| [NFExerciseScoringEngine.swift](../../Sources/TrainingEngine/NFExerciseScoringEngine.swift) | Schema validation, input validation, response grading, feedback | SCO-001–019 and QA-S01–S16, including the new AI grading service integration. |
| [NFBundledRetrievalCatalog.swift](../../Sources/TrainingEngine/NFBundledRetrievalCatalog.swift) | 200 editorial targets, 800 computed instances, exact-string aliases/normalizer | SCO-009–014, CON-010/016/026, QA-F43–F51. |
| [NFEstimateExactContract.swift](../../Sources/TrainingEngine/NFEstimateExactContract.swift) | Estimate/plausibility/exact fields encoded as logic state | SCO-015/016 and QA-S05/S07. |
| [NFQuestionFingerprint.swift](../../Sources/TrainingEngine/NFQuestionFingerprint.swift) | Existing novelty canonicalization, retrieval target identity | CON-020/021, QA-B05/B07. |
| [NFOfflineQuestionBank.swift](../../Sources/TrainingEngine/NFOfflineQuestionBank.swift) | First-unique admission, 1,000-per-lab floor, signed coverage gate | CON-014–022 and QA-B01/B08/B09. |
| [NFOfflineQuestionRotation.swift](../../Sources/TrainingEngine/NFOfflineQuestionRotation.swift) | Versioned IDs, reservation ledgers, epoch/cursor and boundary exclusions | CON-017–019; state chapter owns transaction implementation. |
| [UniversalSessionView.swift](../../Sources/Features/Training/UniversalSessionView.swift) | Renders context/representations and current response controls | CON-004/008 and SCO-014/016; interaction chapter owns screens. |
| [OfflineQuestionBankTests.swift](../../Tests/OfflineQuestionBankTests.swift) | Canonical-key, uniqueness, and at-least-one-family tests | Extend with semantic truth, family capacity, and distribution gates rather than relying on current coverage alone. |
| [ExecutedProbeResults.txt](../QA_2026-09-04/ExecutedProbeResults.txt) | Actual application evidence for bad items, grading, distributions, and metadata-only difficulty | Baseline comparison for corrective acceptance tests. |

The one external statistical reference in section 3 supports the specific warning about comparing separate confidence intervals. The quotas, four editorial bands, parser resource limits, suggested practice partial-credit formula, and 28-session editorial review set are proposed product/engineering policies. None is represented as an externally validated psychometric standard.
