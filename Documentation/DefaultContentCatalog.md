# Default content catalog

> **Scope of this guide:** this describes the existing implementation/deployment. The [revised product direction](AI_Product_Direction_2026-09-05.md) permits integrated local/cloud AI tutoring, grading and generation. Existing Shortcut consent mechanics and bundled-inventory signing requirements are not general admission gates for the new AI features. This documentation revision changes no deployed behavior.

NeuroForge ships **7,000 canonical offline questions: 1,000 in each of seven labs**, organized into 58 deterministic activity families. Every family can be launched with any of the eight supported STEM field perspectives, giving 464 selectable activity–field pairings before parameter, representation, and locale variation. Field choice changes visible framing only where a reviewed domain profile supports it; renamed nouns, option shuffles, new IDs, display skins, and difficulty labels do not count as new questions. All activities work offline and use the same typed exercise schemas, authoritative scorer, confidence capture, feedback, evidence classes, and session persistence as Today.

The release audit canonicalizes the task, essential stimulus, and authoritative response contract. It requires 1,000 distinct fingerprints per lab and generates, validates, and correctly scores every admitted contract. Retrieval Practice has the same 1,000-question floor plus a stricter identity audit: it contains 200 editorial concept targets and 800 computed instances across 80 deterministic calculation families, balanced at 125 contracts in each of eight STEM fields. A response-form change alone never creates a new contract; a computed instance must change the substantive givens and authoritative answer.

Mixed focused quizzes reserve a persistent per-profile, per-lab shuffled slice **at launch**. A quit-before-answer therefore still advances the cursor. Questions are drawn without replacement through the 1,000-item epoch, a quiz crossing an epoch cannot duplicate an item, and the prior epoch tail is delayed at the next boundary. Selected activities have independent launch lanes: abandoning one advances its launch seed, and a session-level fingerprint exclusion broadens to other reviewed families in the same lab when a narrow activity exhausts its meaningful variants. Tests cover all 58 selected activities and require two consecutive 10-question launches to have no within-run duplicate and no identical full sequence. A narrowly defined activity can still share an opening contract across launches; the 1,000-without-replacement guarantee belongs to the mixed lab bank, not to each individual activity family.

## Coverage

| Lab | Offline questions | Families | Examples |
| --- | ---: | ---: | --- |
| Mental Mathematics | 1,000 | 10 | rapid recall, compensation, representation relay, scientific notation repair, missing factor, error detection, calculation chain, estimate-first, tool judgment, strategy comparison |
| Spatial Reasoning | 1,000 | 6 | coordinate and object rotation, cross-sections, orthographic views, algorithmically validated cube nets, vector reflection |
| Quantitative Intuition | 1,000 | 8 | proportions, Fermi estimates, unit conversion, scaling laws, Bayes with natural frequencies, expected value, regression to the mean, interval interpretation |
| Scientific Reasoning | 1,000 | 9 | claim/evidence bounds, confounds, discriminating experiments, figure uncertainty, design repair, competing predictions, reviewer audit, experiment ordering, paper structure |
| Logic & Debugging | 1,000 | 9 | state traces, necessary/sufficient conditions, counterexamples, proof ordering, invalid-step localization, boundary bugs, complexity, loop repair, confidence calibration |
| Retrieval Practice | 1,000 | 9 | 200 editorial concept targets plus 800 computed instances across 80 calculation families, exercised through active recall, reconstruction, recognition auditing, retrieval-cycle ordering, source-figure interpretation, and source-filter tracing |
| Transfer Lab | 1,000 | 7 | problem-solving sequence, transfer conditions, field-shifted rates, table-to-equation, causal structure, interacting variables, saturation limits |

The signed release inventory remains a separate integrity layer. Its manifest and signature were not changed for this 7,000-question bank because the offline private release-signing key is deliberately absent from the repository. The bank mapping is currently compiled/code-signed application metadata, while runtime and unit audits pin its count, identities, semantics, schema validity, and scoring. This is **not** a substitute for content-manifest signing: before this catalog ships, the release authority must independently review the bank, add the mapping and retrieval targets to the signed inventory, bump the content version, and re-sign it (or approve a signed release exception under the product specification).

Every learner-selected catalog activity—including activities in the Transfer Lab—is recorded as **practice**. Near-transfer, applied-transfer, retention, and protected assessment evidence can be created only by scheduled tasks that carry the required origin, exposure, and target-form metadata.

## Why puzzles are included

Puzzle presentation is used only when the puzzle action *is* the target operation: folding a cube net, finding a minimal counterexample, ordering proof dependencies, tracing state, locating a boundary bug, auditing a calculation, or mapping a causal structure. Puzzle labels are an interaction choice, not evidence that gamification improves cognition.

NeuroForge does not include generic n-back, digit-span, memory-grid, “brain age,” IQ, or attention games in this catalog. Working-memory training findings are strongest on tasks similar to training and do not justify fluid-intelligence claims. Temporary state maintenance appears only inside authentic calculations, transformations, and program traces.

## Research-to-product rules

| Finding | Catalog and scheduling consequence |
| --- | --- |
| Retrieval before review generally improves delayed retention compared with restudy. | Recall and reconstruction activities require an answer before reveal, then show comparison feedback and encourage a closed-reference retry. |
| The useful spacing interval depends on the intended retention delay. | Scheduling adapts from stored evidence; the catalog does not claim a universal fixed “1–3–7–21” schedule. NeuroForge's precise timing policy is a versioned product heuristic, not a validated estimate of an individual's memory. |
| Interleaving effects vary substantially by content and task similarity. | The current mixed mode rotates formats within a lab. It is not presented as competence-gated or evidence-validated interleaving of confusable methods. |
| Spatial skills are trainable on average, with some durability and transfer. | Spatial puzzles vary transformations and representations, while unfamiliar forms remain separate transfer evidence. |
| Comparing structurally analogous cases can support learning. | Transfer Lab activities practice mapping roles and constraints; performance does not enter a transfer evidence class until a separate unfamiliar check. |
| Games can support learning, but effects depend on mechanics and study quality. | The universal session preserves deterministic feedback and evidence semantics; rewards, speed, or a game shell cannot change scoring authority. |

## Reviewed references

- SCI-01 — Melby-Lervåg, Redick, & Hulme (2016), *Working Memory Training Does Not Improve Performance on Measures of Intelligence or Other Measures of “Far Transfer”*. [DOI](https://doi.org/10.1177/1745691616635612)
- SCI-02 — Rodas et al. (2024), *Can we enhance working memory? Bias and effectiveness in cognitive training*. [PubMed](https://pubmed.ncbi.nlm.nih.gov/38366265/)
- SCI-03 — Uttal et al. (2013), *The malleability of spatial skills: a meta-analysis of training studies*. [PubMed](https://pubmed.ncbi.nlm.nih.gov/22663761/)
- SCI-04 — Roediger & Karpicke (2006), *Test-enhanced learning: taking memory tests improves long-term retention*. [DOI](https://doi.org/10.1111/j.1467-9280.2006.01693.x)
- SCI-05 — Cepeda et al. (2006), *Distributed practice in verbal recall tasks: a review and quantitative synthesis*. [PubMed](https://pubmed.ncbi.nlm.nih.gov/16719566/)
- SCI-06 — Pan & Rickard (2018), *Transfer of test-enhanced learning: meta-analytic review and synthesis*. [DOI](https://doi.org/10.1037/bul0000151)
- SCI-07 — Alfieri, Nokes-Malach, & Schunn (2013), *Learning through case comparisons: a meta-analytic review*. [DOI](https://doi.org/10.1080/00461520.2013.775712)
- SCI-08 — McDowell & Jacobs (2017), *Meta-analysis of the effect of natural frequencies on Bayesian reasoning*. [PubMed](https://pubmed.ncbi.nlm.nih.gov/29048176/)
- Rowland (2014), *The effect of testing versus restudy on retention: a meta-analytic review of the testing effect*. [PubMed](https://pubmed.ncbi.nlm.nih.gov/25150680/)
- Brunmair & Richter (2019), *Similarity matters: a meta-analysis of interleaved learning and its moderators*. [DOI](https://doi.org/10.1037/bul0000209)
- Clark, Tanner-Smith, & Killingsworth (2016), *Digital Games, Design, and Learning: A Systematic Review and Meta-Analysis*. [PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC4748544/)

## Claim boundary

Safe progress language remains narrow and inspectable:

- “Accuracy improved on practiced compensation problems.”
- “Performance was higher on four previously unseen forms in this app.”
- “This relationship was recalled after a 14-day delay.”
- “The skill also appeared on two unfamiliar checks; more evidence is needed.”

The catalog does not support claims such as “sharper brain,” “improved working-memory capacity,” “higher IQ,” or general improvement in mathematics, science, or programming based only on practiced activity scores.
