# NeuroForge question-content QA — 2026-09-04

Scope: source inspection of the seven deterministic fallback lab generators, offline question admission/fingerprints, bundled retrieval contracts, relevant response scoring, content tests, and pre-answer rendering. No application files edited. Findings below separate direct execution from source-derived deterministic reconstruction. This is a substantive content audit, not a claim that every domain fact received independent expert review.

## Conclusion

The core topics are useful (mental arithmetic, units, causal inference, counterexamples, code state, recall, structural transfer), but current interaction packaging and bank composition do not support a consistently professional, challenging learning experience. The 7,000-contract count disguises severe repetition in several mixed labs; some keyed questions are objectively inconsistent; open answers suffer both false rejection and false acceptance. Existing integrity tests primarily establish that the stored key scores as correct, not that the key is true, unique, fair, or pedagogically useful.

## P1 — Incorrect or unfair scoring/content; fix before treating results as trustworthy

### C1. Coordinate rotation can show two identical correct answers and mark one wrong

- `Sources/TrainingEngine/NFFallbackExerciseGenerator.swift:658`–675 chooses x=2...41 and y=1...40, sets the correct option to (-y,x), and a distractor to (-x,y). When x=y these are identical.
- `Sources/TrainingEngine/NFFallbackExerciseGenerator.swift:817`–833 creates separate IDs (`correct` and `distractor.2`) even for identical text.
- `Sources/TrainingEngine/NFExerciseScoringEngine.swift:171` only checks option-ID uniqueness; :936–946 scores by correctOptionID.
- Reproduction derived from the exact FNV/SplitMix seed logic: generate seed **11**, index 0, lab `spatial`, purpose `practice`, other arguments default. Point is **(10,10)**; two choices both say **(-10,10)** and only one receives credit.
- The defect affects 39/1600 possible coordinate pairs, not only one seed.
- Fix: reject semantically equivalent distractors before publishing a question; assess all option values, not only IDs. Add parameter-boundary tests for symmetry points.

### C2. Science uncertainty questions assert overlap for disjoint intervals

- `Sources/TrainingEngine/NFFallbackExerciseGenerator.swift:1457`–1458 sets low=15...64 and high−low=3...22.
- :1481 gives A interval [low−3,low+5], B [high−5,high+3]. These are disjoint whenever high−low>10.
- Nevertheless :1467 keys “overlapping uncertainty” as correct, :1474 says the intervals overlap, and :1482 states overlap in accessibility text. All three other options also make invalid stronger claims, so the item can have no fully correct choice.
- Thus **12/20 possible mean differences (60%)** contradict their own data.
- Deterministic reconstruction of the 1,000-item science bank finds **266 affected items**. Example ordinal **9**, candidate 24, seed **8424208090942894707**: A mean 21 with interval 18–26; B mean 32 with interval 27–35. They do not overlap.
- Fix: derive narrative/key/accessibility text from computed interval state; specify what interval means; include both overlap/nonoverlap cases with claim rules tied to the study design. Independently verify numerical stimulus against every statement in the item.

### C3. Correct free-text and mathematical answers are rejected

- `Sources/TrainingEngine/NFFallbackExerciseGenerator.swift:2212`–2250 and :2284–2302 applies normalized exact matching to short-answer/cloze/equation/figure retrieval.
- `Sources/TrainingEngine/NFExerciseScoringEngine.swift:754`–766, :1014–1021 performs string equality against a short finite list.
- Direct Swift execution of the repository's **unchanged** `NFBundledRetrievalCatalog` and `accepts` implementation produced:

| Question target | Submitted valid answer | Current result |
|---|---|---|
| Arithmetic mean | “Sum all observations then divide by their count” | Rejected |
| Falsifiable hypothesis | “An observation could disprove it” | Rejected |
| Independent variable | “The manipulated variable” | Rejected |
| Median | “For odd n take the middle observation; for even n average the middle two observations” | Rejected |
| Derivative of x² | `2*x` | Rejected; key is `2x` |
| Derivative of 2x² | `4x` | Rejected; key is `4x^1` |
| Control-group purpose | “To provide a baseline against which to compare the treatment group” | Rejected |
| Binary representation of 33 | `0100001` | Rejected; key `100001` |

- Asking “How many centimetres are in exactly 2 metres?” rejects `200` because the short-text key requires `200 centimetres`/`200 cm`, although the prompt already gives the requested unit. This is an instruction/response-contract mismatch rather than incorrect arithmetic.
- Fix: typed numeric/unit and restricted symbolic contracts for computed answers; constrained concept rubrics or self-check with honest ungraded status for explanatory prose. Add reasonable paraphrases, symbol equivalences, and minimal-answer cases to a curated acceptance test set; keep negation/contradiction probes. Do not solve this by indiscriminate fuzzy matching.

### C4. Exact-answer normalization also accepts an incorrect calculus answer

- `Sources/TrainingEngine/NFBundledRetrievalCatalog.swift:180` asks “If F prime equals f, what is the definite integral of f from a to b?” Key is `F(b) - F(a)`.
- `.../NFBundledRetrievalCatalog.swift:1617`–1625 case-folds all identifiers. Direct Swift execution accepts **`f(b) - f(a)`**, which evaluates the integrand at endpoints instead of the antiderivative.
- Fix: separate prose normalization from case-sensitive mathematical identifier parsing; validate semantic symbol roles.

### C5. Accepted equivalent responses can be “correct” but receive partial credit

- `Sources/TrainingEngine/NFEstimateExactContract.swift:19`–47 explicitly creates accepted states for alternatives such as `yes` versus `plausible`, or formatted numbers.
- `Sources/TrainingEngine/NFExerciseScoringEngine.swift:1139`–1154 checks correctness against all accepted states but computes credit by literal equality to **only the canonical** dictionary. :801/:843 returns that raw credit unchanged.
- Source-level example: a fully correct estimate/exact submission using accepted `yes` instead of canonical `plausible` is correct but receives only **2/3 credit**; using all three accepted alternative spellings can receive **0 credit while correct**.
- Fix: full credit for any authoritative accepted equivalent state; for partial credit, compare each field to that field's accepted equivalents. Test display text, stored correctness, stored credit, and progress consequences together.

## P1/P2 — Challenge, variety, and measurement validity

### C6. “1,000 questions per lab” heavily concentrates on one or two mechanics

- `Sources/TrainingEngine/NFOfflineQuestionBank.swift:118`–143 takes the first 1,000 distinct canonical contracts. It imposes no mechanic quota.
- `Sources/TrainingEngine/NFFallbackExerciseGenerator.swift:2514` provides 2,000 rate×time parameter pairs. The other six transfer variants provide only 14 distinct contracts altogether (1 sequence,1 condition selection,4 equations,1 claim mapping,6 ratio values,1 saturation check).
- Deterministic reconstruction from the exact FNV/SplitMix random functions and canonical varying fields:

| Mixed offline bank | Composition |
|---|---|
| Transfer | **986/1000 rate×time**; six other families share 14 |
| Logic & Debugging | **990/1000 stale-derived-state traces**; seven fixed other questions plus three confidence-rate cases |
| Scientific Reasoning | **557 mean/evidence mappings +436 uncertainty items**; seven other families appear once each |
| Retrieval |1,000 distinct knowledge targets; however101 are rendered as the same fixed retrieval-cycle ordering question |

- Bank final candidate indices reconstructed: transfer 9620; logic 9355; science 5636; retrieval 8480. Script at `/private/tmp/neuroforge-bank-distribution.py`.
- These exact distribution counts are a source-derived reconstruction, not a separately instrumented application-bank dump. The transfer≥986 and logic≥990 concentration bounds follow directly from the finite number of other contracts even without the reconstruction.
- `Tests/OfflineQuestionBankTests.swift:47` only requires each family appear at least once; the test therefore permits these concentrations.
- Consequence: shuffled unique numbers do not feel like varied learning. A 10-question mixed Transfer quiz will usually be multiplication repeatedly despite seven advertised families.
- Fix: stratified, quota-based admission and runtime family balancing; add materially different scenarios before expanding numeric counts. Report both concept/mechanic count and parameterized item count in QA. Put a maximum consecutive-family limit in mixed practice and add distribution tests.

### C7. Pre-answer content supplies answers, including for protected checks

- `Sources/Features/Training/UniversalSessionView.swift:1377` renders context before the prompt; :1395 renders representations before the response. These have no protected-assessment filter.
- `Sources/TrainingEngine/NFFallbackExerciseGenerator.swift:1923` states “Because a equals b, the proposed divisor is zero” for the invalid-proof question.
- :1870 displays `2×3=6`, exactly the keyed counterexample option.
- :1433 tells the learner to change A independently and use a calibrated measurement before asking which experiment is best.
- :1835 explains that all multiples of 4 are even but 2 and 6 are not multiples of 4, doing the necessity/sufficiency inference for the user.
- Only `hintLadder` is removed for protected purposes (:172); same draft context/representations still ship. These are legitimate worked-example scaffolds in teaching mode but contaminate unaided baseline/assessment evidence.
- Fix: explicit teaching/assisted practice/independent check presentations; content contract declares which representations are essential givens versus solution scaffolds. Remove only solution cues in independent modes and track requested assistance separately.

### C8. Retrieval “variety” often changes labels, not the cognitive operation

- `NFFallbackExerciseGenerator.swift:2225` cloze is the ordinary question prefixed “Cloze reconstruction,” without an actual sentence blank.
- :2284 equation reconstruction adds generic `E_source+C_stated→□`, unrelated to many fact targets.
- :2303 figure interpretation repeats the fact question in a two-row text table; it is not a source figure/data interpretation exercise.
- :2265 retrieval-cycle ordering always grades `retrieve→compare→locate→retry`, regardless of target; answering does not demonstrate knowledge of that target.
- :2320 source-filter tracing always returns the supported option from fixed pseudocode.
- :2251 and :2320 use the same generic reversed/universal/omitted distractors for every topic. For “SI unit of time”, `second` is contrasted with three long generic relationship statements. The answer can be found by grammar or length without knowing the subject.
- Fix: author genuine target-specific cloze deletions, equation slots, diagrams, trace outputs, and misconception distractors. Hide unsupported interaction types for targets that lack the needed assets. Tag metacognitive workflow tasks separately from retrieval mastery.

### C9. Several activity names promise a deeper task than implemented

- `NFDefaultContentCatalog.swift:222` 3D Object Rotation summary advertises tracking labeled faces, but `NFFallbackExerciseGenerator.swift:682`–706 transforms a single coordinate triple90° about z. This is essentially the 2D rotation rule with z unchanged.
- Top-View Decoder advertises occupied positions/hidden height but :740–763 asks which two dimensions of a rectangular block remain in its top view.
- Fermi Estimate (:969–1001) supplies every factor and the multiplication equation, so it mainly tests arithmetic rather than building assumptions or estimating unknown factors.
- Paper Sprint (:1630 onward) contains no unfamiliar abstract to read; it asks for one fixed reading order.
- Fix names to match present capabilities, then implement real spatial objects/views, assumption entry + sensitivity comparisons, and short synthetic abstracts with evidence extraction.

### C10. Estimate tasks use rigid text keys rather than estimating

- `NFFallbackExerciseGenerator.swift:456`–499 asks for an estimate and plausibility judgment, but only accepts `10000` (or its formatted spelling) for products near 200×50 and `plausible`/`yes`; no range or numeric equivalence.
- :1024–1040 metric estimate asks a reasonable estimate, but only accepts one rounded integer with one exact wording plus a bare alternative. E.g. 1.25 m may reasonably be estimated 1.3 m but only about 1 m / 1 m is accepted.
- `NFExerciseScoringEngine.swift:1140` uses literal whole-dictionary equality without whitespace/case normalization.
- Fix estimates with bounded numeric intervals or explicit “nearest power of ten” instructions; use buttons for plausibility and numeric fields with unit controls; grade calculation, scale judgement, and estimation separately.

## Question usefulness and difficulty judgement

Useful: basics of numeracy, dimensions, proportion, common-cause reasoning, counterexamples, code invariants, and recall are teachable skills. Deterministic math keys, restricted interpreted code, cube-net validation, distractor error codes, and separation of practice versus transfer evidence are valuable foundations.

Not yet sufficient: most items are one-rule textbook exercises, many fixed questions expose their method before the response, and the bank overweights the biggest numeric parameter spaces. This can support novice drills but offers limited sustained challenge for experienced STEM learners. The content alone does not establish improved general reasoning or real-world skill; application must be tested with genuinely unseen, richer tasks.

Difficulty caveat: `NFFallbackExerciseGenerator.swift:3153`–3175 changes reported difficulty metadata; number ranges and reasoning steps remain fixed for a given seed. Parent adaptive audit owns the end-to-end adaptation analysis.

## Improvement plan for content

1. **Trust first (P1):** block bad coordinate/interval items, repair mathematical/prose scoring separation, fix accepted-equivalent credit, remove assessment answer cues. Add independent truth/ambiguity/acceptance tests; do not rely on submitting the stored key back to the scorer.
2. **Variety next (P1):** balance mixed sessions by mechanic/concept and difficulty, add missing scenario families, prevent repeated same-method drills unless intentionally selected. Set a per-family cap and minimum field/context coverage.
3. **Real learning interactions (P2):** progressive worked examples; stepwise code tracing and patch execution against visible boundary tests; draggable causal graph roles and experiment outcomes; rotatable 3D objects for practice and static novel orientations for unaided checks; Fermi factor entry + range propagation; real equation reconstruction; authentic short abstracts/plots with evidence extraction.
4. **Editorial standards (P2):** each item has objective, prerequisites, independently verified key, plausible misconception distractors, assistance policy, explanation of why each choice is wrong, accepted-equivalence contract, and source/context where relevant. Teach simple concepts before highly technical wording.
5. **Measure learning quality (P2):** record item difficulty/pass rates, distractor selections, hint use, disputed grading, abandonment, response time, and later retention by mechanic. Use this to identify easy answer cues and bad items; add “Report a question problem” with the question version/seed attached.

Suggested acceptance gates: zero duplicate answer values; zero stimulus/key contradictions over complete bounded parameter domains; full credit for all declared equivalents; no solution scaffold on independent checks; every reported mechanic reaches an agreed mixed-session share; target-specific distractors survive a blind review; novice/intermediate/advanced sample sessions have visibly different demands; an editorial audit tests plausible valid/invalid responses rather than merely each canonical key.

## Executed checks and limits

- Direct Swift execution of unchanged retrieval catalog with only a stand-in enum for STEMField: all 1,000 contracts loaded, `audit()` returned `[]`; exported to `/private/tmp/neuroforge-retrieval-1000.json`.
- Ten targeted answer-acceptance probes executed; eight correct natural/mathematical alternatives rejected, one unit-omitted response rejected, one incorrect case-sensitive calculus response accepted. Harness: `/private/tmp/neuroforge-catalog-audit.swift`.
- Deterministic bank-distribution reconstruction and interval arithmetic enumeration: `/private/tmp/neuroforge-bank-distribution.py`.
- Source inspection of actual scorer and UI confirms ID-only choice grading, literal state matching, and always-visible context/representations.
- Application build, UI flow QA, adaptive scheduling, persistence, device accessibility, and integration results are owned by the other reviewers. No claim of exhaustive expert factual review of all 1,000 retrieval targets or every possible generated exercise.
