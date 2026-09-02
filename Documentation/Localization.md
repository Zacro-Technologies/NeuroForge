# NeuroForge localization notes

The source language is English. Japanese catalog values in the release-candidate repository are production-oriented drafts and require a native-speaker review before store submission. Product and Apple technology names must follow the spelling in Apple's Japanese style guidance.

## Scientific and product glossary

| English source term | Preferred Japanese | Translator note |
| --- | --- | --- |
| NeuroForge | NeuroForge | Product name; never translate. |
| STEM | STEM | Keep the acronym in Latin characters. |
| Question Writer | 問題作成 | NeuroForge feature name for a user-owned, user-configured Shortcut. It is a route, not an attested model provider. |
| Question Writer Shortcut | 問題作成ショートカット | Use when the Shortcut itself must be named. Do not imply that NeuroForge selects or verifies its provider. |
| ChatGPT | ChatGPT | Recommended user selection in the Shortcut’s Use Model action. Keep the product name in Latin characters and do not imply a direct NeuroForge API integration. |
| Use Model | モデルを使用 | Apple Shortcuts action name. Follow the final localized label shown by the target OS. |
| Apple Pencil | Apple Pencil | Apple product name. |
| iCloud | iCloud | Apple product name. |
| Spotlight | Spotlight | Apple product name. |
| skill check | スキルチェック | The optional initial four-block assessment, not a population norm. |
| evidence | エビデンス | App-specific observations; never imply clinical or population evidence. |
| skill estimate | スキル推定 | An in-app estimate, not intelligence or aptitude. |
| transfer | 転移 | Applying a practiced structure in an unfamiliar representation or context. Prefer 応用 only when 転移 would be unnatural in compact interface copy. |
| near transfer | 近接転移 | A related but unfamiliar form. |
| retention | 保持 | Recall after a delay; 復習 is acceptable for an action label, not for the evidence channel. |
| holdout / protected form | ホールドアウト / 保護されたフォーム | Previously unexposed assessment content. Do not imply secrecy or security certification. |
| confidence calibration | 確信度の較正 | Comparing stated confidence with observed correctness; not a judgment of the person. |
| deterministic | 決定論的 | Computed by fixed application rules rather than a model. |
| citation / cited excerpt | 引用 / 引用された抜粋 | A source link does not establish the source's real-world truth. Keep “source link” distinct from an independently verified citation. |
| bounded excerpt | 範囲制限された抜粋 | Text selected from an identified source for one approved Question Writer run: at most four excerpts, 1,600 characters each and 4,800 total. Do not imply that the consent dialog previews the full text. |
| OCR | OCR | Optical character recognition performed locally for supported PDFs and images. |

## Style and format contracts

- Use polite, direct Japanese and neutral language around missed practice, low evidence, errors, and uncertainty.
- Preserve every limitation in privacy, educational-use, AI-routing, scoring, and evidence disclosures.
- Describe ChatGPT as recommended, never as selected, enforced, or attested by NeuroForge. Preserve that the learner controls the provider in Shortcuts.
- In source-sharing copy, distinguish the local original from bounded excerpts and preserve the per-run consent and numeric limits exactly. Do not claim that the consent dialog displays full excerpt text.
- Preserve Apple product names, `NeuroForge`, stable machine-readable identifiers, and all format placeholders exactly.
- Positional placeholders such as `%1$lld` and `%2$@` may be reordered only by preserving their positional index and type.
- `${applicationName}` is App Shortcuts metadata and must remain byte-for-byte intact.
- Dates, times, numbers, percentages, byte counts, and durations must be produced by locale-aware Foundation format styles; do not insert English-formatted values into Japanese prose.
- Strings that describe deterministic exercise content must not change the answer authority, numerical value, unit, citation, or scorer contract.
