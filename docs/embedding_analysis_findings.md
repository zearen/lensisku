# Embedding analysis findings report

**Date:** 2025-01-30  
**Scope:** Similarity search and embedding content (definition, notes, glosswords) by valsi type.  
**Data source:** Local database via `psql` (PostgreSQL MCP tool was not available in this session; script run manually).

---

## 1. How the analysis was run

- **Plan followed:** `docs/embedding_improvement_plan.md`
- **Scripts:** `scripts/analyze_embedding_content.sql` (content by type, notes/definition length, fallback counts); `scripts/analyze_embedding_skew_patterns.sql` (formatting, service phrases, high-frequency words, definition prefixes, glossword tokens).
- **Execution:** `psql "$DATABASE_URL" -f scripts/analyze_embedding_content.sql` and `psql "$DATABASE_URL" -f scripts/analyze_embedding_skew_patterns.sql` against local DB.
- **PostgreSQL MCP:** Tool name for query execution was not found; analysis used direct `psql` instead. When MCP is configured, the same script can be run via the MCP query tool.

---

## 2. Valisi types and definition counts

| typeid | type_name        | def_count |
|--------|------------------|-----------|
| 4      | lujvo            | 14,749    |
| 1      | gismu            | 14,745    |
| 5      | fu'ivla          | 12,901    |
| 2      | cmavo            | 3,404     |
| 6      | cmavo-compound   | 2,447     |
| 8      | experimental cmavo | 1,121  |
| 3      | cmevla           | 891       |
| 7      | experimental gismu | 710     |
| 12     | obsolete fu'ivla | 432       |
| 10     | zei-lujvo        | 177       |
| 11     | obsolete cmevla  | 101       |
| 9      | bu-letteral      | 89        |
| 13     | obsolete zei-lujvo | 4       |
| 14     | obsolete cmavo   | 3         |
| 0      | nalvla           | 1         |
| 15     | phrase           | 0         |

**Finding:** 16 types; bulk of definitions are lujvo, gismu, fu'ivla, then cmavo and experimental/cmavo-compound. Experimental and obsolete types have smaller but non-trivial counts.

---

## 3. By type: definition vs notes length, % with glosswords

| type_name           | defs  | avg_def_len | avg_notes_len | with_glosswords | pct_glosswords |
|---------------------|-------|-------------|---------------|----------------|----------------|
| lujvo               | 14749 | 77          | 72            | 13406          | 90.9           |
| gismu               | 14745 | 67          | 88            | 10441          | 70.8           |
| fu'ivla             | 12901 | 67          | 42            | 11997          | 93.0           |
| cmavo               | 3404  | 53          | 42            | 2453           | 72.1           |
| cmavo-compound      | 2447  | 55          | 84            | 1892           | 77.3           |
| **experimental cmavo** | 1121 | **85**      | **344**       | 798            | 71.2           |
| cmevla              | 891   | 19          | 80            | 689            | 77.3           |
| **experimental gismu** | 710  | **102**     | **206**       | 524            | 73.8           |
| obsolete fu'ivla    | 432   | 72          | 83            | 386            | 89.4           |
| zei-lujvo           | 177   | 88          | 77            | 119            | 67.2           |
| obsolete cmevla     | 101   | 11          | 73            | 97             | 96.0           |
| bu-letteral         | 89    | 30          | 65            | 67             | 75.3           |
| obsolete zei-lujvo  | 4     | 92          | 164           | 4              | 100.0          |
| obsolete cmavo      | 3     | 115         | 184           | 3              | 100.0          |
| nalvla              | 1     | 61          | (null)        | 1              | 100.0          |

**Findings:**

- **experimental cmavo:** avg notes length **344** vs def **85** → notes are ~4× definition length and will dominate the embedding when we use definition+notes (fallback). Strong skew risk.
- **experimental gismu:** avg notes **206** vs def **102** → notes ~2× definition; still strong skew.
- **obsolete cmavo / obsolete zei-lujvo:** very high avg_notes_len (184, 164) and 100% fallback (no glosswords) → notes dominate.
- **gismu / lujvo / cmavo:** notes and definition lengths are comparable; skew from length is lower, but gismu has the largest number of fallback-only definitions (see below).

---

## 4. Definitions where notes are much longer than definition (skew candidates)

Top rows are dominated by:

- **experimental cmavo** (e.g. bi'oi'au, ji'i'u, go'ei, mi'i'au, rai'i, sei'au, bi'oi, fei'i, de'ai, xo'au, xoi'ei'a, zu'ei): notes 2,300–5,400 chars vs definition 37–676 chars. Notes contain long formal/math explanations, usage rules, and boilerplate.
- **fu'ivla** (e.g. aigne, cnanfadi, tcaudu, zenbaje, tcasnuue): notes 2,400–4,600 chars with technical/math elaboration. So for some fu'ivla, notes can still skew embeddings when there are no glosswords.

**Finding:** Excluding or capping notes for **experimental cmavo** (and similar types) is well supported. For **fu'ivla**, a length-based rule (e.g. exclude notes when notes > 2× definition length) could help in the fallback path.

---

## 5. Experimental cmavo / gismu: sample notes

**Experimental cmavo (long notes):**  
Samples show notes like: “Note: {ro} is preferred if…”, “1. The first place containing abstraction…”, “This experimental cmavo form has been assigned meanings…”, and long usage/grammar text. So notes are often repetitive, structural, or boilerplate rather than core meaning.

**Experimental gismu (sample from script):**  
Notes are shorter: “See {cipnrkorvo}”, “{rutrmango} is the non-experimental synonym…”, or empty. So for experimental gismu, excluding notes is still useful (avoids “See …” and synonym boilerplate) and is supported by avg_notes_len being ~2× definition.

---

## 6. Fallback-only definitions (no glosswords)

These are definitions we embed as **definition + notes** (or definition-only when `skip_notes_for_embedding_type` applies):

| type_name           | fallback_count |
|---------------------|----------------|
| gismu               | **4,304**     |
| lujvo               | 1,343          |
| cmavo               | 951            |
| fu'ivla             | 904            |
| cmavo-compound      | 555            |
| experimental cmavo  | 323            |
| cmevla              | 202            |
| experimental gismu  | 186            |
| zei-lujvo           | 58             |
| obsolete fu'ivla    | 46             |
| bu-letteral         | 22             |
| obsolete cmevla     | 4              |

**Finding:** Gismu and lujvo have the most fallback-only definitions. For them, definition and notes lengths are similar on average, so current “definition + notes” is less obviously skewed than for experimental cmavo/gismu. The main gain comes from **not** including notes for experimental/obsolete types (already implemented).

---

## 7. Alignment with current implementation

- **`skip_notes_for_embedding_type`** currently excludes notes for:  
  `experimental cmavo`, `experimental gismu`, `obsolete cmavo`, `obsolete gismu`.

- **Data supports this:**  
  - experimental cmavo: avg_notes 344 vs def 85; experimental gismu: 206 vs 102.  
  - obsolete cmavo/zei-lujvo have 100% fallback and very long notes.  
  Including obsolete zei-lujvo in the skip list would be consistent (we do not add it by default only because count is 4; you can add it if you see boilerplate).

- **Obsolete fu'ivla:** 432 defs, avg_notes 83, 46 fallback. Notes are not as extreme as experimental cmavo; optional future improvement is to add “obsolete fu'ivla” to the skip list if notes are mostly boilerplate.

---

## 8. What else can skew similarity search: formatting, service words, structural boilerplate

**Script:** `scripts/analyze_embedding_skew_patterns.sql` (run: `psql "$DATABASE_URL" -f scripts/analyze_embedding_skew_patterns.sql`).

### 8.1 Formatting in definition/notes (raw content)

| Pattern        | Definitions containing | %   |
|----------------|------------------------|-----|
| math `$...$`   | 44,435                 | 85.8 |
| braces `{...}` | 34,977                 | 67.6 |
| quotes `"..."` | 1,821                  | 3.5  |

**Finding:** Most definitions contain math placeholders (`$x_1$`, `$x_2$`, etc.) and/or Lojban braces (`{broda}`). The current preprocessor replaces these with `[UNK]`, so the embedding sees a lot of identical `[UNK]` tokens. That can **cluster many definitions** (e.g. “x is [UNK] of [UNK]”) and dilute the semantic signal. Quotes are rarer and already normalized to `[UNK]`.

### 8.2 Service phrases and structural patterns (prevalence)

| Pattern       | Defs containing | %   |
|---------------|-----------------|-----|
| `$x_1$`       | 28,398          | 54.8 |
| `x_2`         | 18,922          | 36.5 |
| See also      | 12,667          | 24.5 |
| sumti         | 985             | 1.9  |
| (ka)          | 599             | 1.2  |
| bridi / selbri| 486 / 458       | ~0.9 |
| selma'o       | 308             | 0.6  |
| (du'u), mekso | 249, 193        | 0.5, 0.4 |
| experimental, cmavo list | 115, 85 | 0.2 |
| Terminated by, ordered list/pair | 22–34 | &lt;0.1 |

**Finding:** “See also” and “See” are already **stripped** by `preprocess_definition_for_vectors`; math and braces become `[UNK]`. So the main remaining structural skew is the **shared prefix** many definitions have (see 8.4). Lojban jargon (sumti, bridi, selbri, selma'o, terbri, gadri) and placeholders like (ka)/(nu)/(du'u) appear in a minority of definitions; (ka)/(nu)/(du'u) are already removed by the preprocessor.

### 8.3 High-frequency “service” words (in definition + notes combined)

Top tokens by occurrence (after splitting on whitespace, length &gt; 1):

| Word       | Occurrences | Likely role |
|------------|-------------|-------------|
| is         | 32,129      | Predicate template “x_1 is …” |
| with       | 21,901      | Common preposition |
| the        | 21,162      | Article |
| of         | 14,901      | Preposition |
| see        | 14,021      | “See also” (we strip “See”) |
| also       | 12,280      | “See also” (we strip) |
| language   | 8,464       | “language with ISO …” boilerplate |
| code       | 8,428       | “ISO 639-3 code” |
| iso        | 7,966       | “ISO 639-3” |
| 639-3      | 7,949       | Same |
| to, in, for| 4,648–7,659 | Common function words |
| cf.        | 3,069       | “cf.” cross-references |
| ・読み方：, ・大意：, ・関連語： | ~1,400–2,260 | Japanese structural labels |
| (lásd, még:, ankaŭ, la, etc.) | ~1,300–1,500 | Other-language boilerplate |

**Finding:** Generic words (“is”, “the”, “of”, “with”) and **structural boilerplate** (“language”, “code”, “iso”, “639-3”) appear very often. Together with the shared definition prefix (next subsection), they can make many **cmevla/language-name** definitions embed very similarly. “See”/“also” are partly mitigated by stripping “See also” and “See”, but “also” can still appear elsewhere.

### 8.4 Definition prefix clustering (structural boilerplate)

Many definitions share the same **leading phrase** (in raw form):

| Prefix (first 30 chars)                    | Count |
|-------------------------------------------|-------|
| `$x_1$ is the language with ISO`         | **7,945** |
| `$x_1$ is the country with the`          | 281   |
| `$x_1$ is measured in currency`        | 174   |
| `$x_1$ is a quantity of/contain`        | 102   |
| `$x_1$ is a part of Lojban text`        | 94    |
| `$x_{1}$ estas kvanto da/enhava` (etc.)  | 61–51 |

**Finding:** **7,945 definitions** start with “$x_1$ is the language with ISO …” (language-name / ISO 639-3 style). After preprocessing this becomes “[UNK] is the language with ISO …”, so a large fraction of definitions share the same opening and will **cluster in embedding space**. This is a major source of skew for semantic search (e.g. “language” or “ISO” queries returning many near-duplicates). Similar but smaller clusters exist for “country”, “currency”, “quantity”, and non-English templates.

### 8.5 Glosswords: repeated tokens

Frequent **gloss** tokens (place = 0) include: Zapotec (59), Mixtec (52), Naga (42), Arabic (40), Quechua (36), Nahuatl (29), Miao (22), love (22), Malay (21), Chinese (20), Dollars (20), etc.

**Finding:** When we embed **glosswords only**, language/ethnic names and a few common words (love, enough, return, duration) repeat across many definitions. That can make “language” or “people” queries return many similar hits. It’s inherent to the data; optional mitigation is to downweight or normalize very frequent gloss tokens when building the embedding string (e.g. skip tokens that appear in &gt; N definitions).

### 8.6 Current preprocessor (what we already do)

- **Replaced with [UNK]:** `$...$` (math), `{...}` (braces), `"..."` (quotes).
- **Removed:** “See also”, “cmavo list”, “See”, “(ka)”, “(nu)”, “(du'u)”, “[UNK] modal,”, trailing “[UNK]”/dots.
- **Normalized:** multiple spaces, repeated dots/commas, leading/trailing punctuation.

So a lot of **formatting** and **Lojban placeholders** are already neutralized; the main remaining skew is **shared structural prefixes** (especially “$x_1$ is the language with ISO”) and **high-frequency service words** (“is”, “the”, “of”, “language”, “code”, “iso”).

---

## 9. Recommendations (from plan + data)

1. **Keep current type-based exclusion**  
   Continue excluding notes for `experimental cmavo`, `experimental gismu`, `obsolete cmavo`, `obsolete gismu` in the fallback path. Data strongly supports this.

2. **Optional: add obsolete zei-lujvo**  
   Only 4 definitions, 100% fallback, avg_notes 164. If descriptor is exactly `obsolete zei-lujvo`, add it to `skip_notes_for_embedding_type` for consistency.

3. **Optional: fu'ivla notes cap**  
   For types that keep notes (e.g. fu'ivla), consider excluding notes in the fallback path when `LENGTH(notes) > 2 * LENGTH(definition)` (or similar) to avoid math/technical elaboration dominating the embedding. This would require passing lengths or a flag from the query into the embedding text builder.

4. **Re-embed after changes**  
   After any change to what goes into the embedding text, set `embedding = NULL` for affected definitions so the background job recalculates:
   - For current implementation: only definitions whose type is in `skip_notes_for_embedding_type` and that use the fallback path (no glosswords) need re-embedding if you previously had notes included.  
   - Simplest: `UPDATE definitions SET embedding = NULL WHERE cached_type_name IN ('experimental cmavo', 'experimental gismu', 'obsolete cmavo', 'obsolete gismu');` then let the job run.

5. **Tune similarity threshold**  
   Current filter `similarity < 0.4` may be too strict or too loose. Consider making it configurable and testing (e.g. 0.35 vs 0.45) on a few representative queries.

6. **PostgreSQL MCP**  
   When the PostgreSQL MCP server is configured and the correct tool name (e.g. `query` or `pg_query`) is known, re-run `scripts/analyze_embedding_content.sql` via MCP for repeatable analysis in future.

7. **Structural prefix / boilerplate (new from §8)**  
   - **Strip or normalize the “language with ISO” prefix:** ~7,945 definitions start with “$x_1$ is the language with ISO …”. Consider adding a preprocessor step that removes or shortens this prefix (e.g. replace with a single token like “language-name” or strip up to the ISO code) so the **distinguishing** part (language name, code) dominates the embedding.  
   - **Optional: strip other common prefixes** (e.g. “$x_1$ is the country with the”, “$x_1$ is measured in currency”) in the same way, or detect “$x_1$ is …” and keep only the unique tail.  
   - **Optional: downweight very frequent gloss tokens** when building embedding text from glosswords (e.g. skip tokens that appear in &gt; 50 definitions) to reduce clustering by language/ethnic names.

---

## 10. Summary

| Question | Finding |
|----------|---------|
| Which part of content skews embeddings? | **Notes**, especially for **experimental cmavo** (avg 344 vs def 85) and **experimental gismu** (206 vs 102). Long fu'ivla notes (math/technical) can also skew when there are no glosswords. |
| Which types have worst notes/def ratio? | experimental cmavo, experimental gismu, obsolete cmavo, obsolete zei-lujvo; then fu'ivla in cases where notes >> definition. |
| Is excluding notes for experimental/obsolete correct? | **Yes.** Data supports excluding notes for experimental cmavo, experimental gismu, obsolete cmavo, obsolete gismu. |
| When is fallback (definition+notes) used most? | Gismu (4,304), lujvo (1,343), cmavo (951), fu'ivla (904). For gismu/lujvo, def and notes lengths are similar; for experimental types, we now correctly drop notes. |
| **What else skews similarity search?** | **Formatting:** 85.8% have math `$...$`, 67.6% braces → replaced with `[UNK]`, so many definitions share the same placeholder text. **Structural boilerplate:** 7,945 definitions start with “$x_1$ is the language with ISO …” → strong clustering. **Service words:** “is”, “the”, “of”, “language”, “code”, “iso” are very frequent. **Glosswords:** repeated language/ethnic names (Zapotec, Mixtec, Arabic, etc.) and a few common words. See §8 and `scripts/analyze_embedding_skew_patterns.sql`. |

The current plan (glosswords-first, placewords always, type-based note exclusion for experimental/obsolete) is aligned with the data. Next steps are re-embedding affected definitions, optional additions (obsolete zei-lujvo, fu'ivla notes cap), **structural-prefix stripping** (especially “language with ISO”), optional downweighting of very frequent gloss tokens, and threshold tuning.
