# Similarity search & embedding improvement plan

## Current implementation (review)

- **Indexed content**: For each definition we embed either (a) glosswords + placewords, or (b) definition + notes + placewords when there are no glosswords. Type suffix `(name)` is appended for cmevla/obsolete cmevla.
- **Preprocessing**: `preprocess_definition_for_vectors()` strips math, braces, quotes, “See also”, “cmavo list”, “See”, and normalizes punctuation/whitespace.
- **Search**: Query text is preprocessed the same way, embedded with the same model; we use cosine distance and filter by `similarity < 0.4` and `score > 0`.

## Why similarity can be poor

1. **Definition/notes length and noise**  
   Long definitions or long notes dominate the vector; boilerplate (e.g. “experimental”, “proposed”, “see …”) can pull embeddings away from the core meaning.

2. **Fallback path**  
   Definitions without glosswords use full definition + notes. If notes are repetitive or off-topic, they skew the embedding.

3. **Type-specific boilerplate**  
   Experimental/obsolete types often have similar notes (e.g. “Experimental cmavo. Not yet in the official list.”), so many definitions cluster by that text instead of meaning.

4. **Threshold**  
   A fixed `similarity < 0.4` may be too strict or too loose depending on language and query.

## Research: what to run locally

Use the analysis script against your DB (or PostgreSQL MCP when available):

```bash
psql "$DATABASE_URL" -f scripts/analyze_embedding_content.sql
```

The script:

- Lists **valsi types** and definition counts (so you know exact `descriptor` values).
- Shows **by type**: avg definition length, avg notes length, % with glosswords (how often fallback is used).
- Finds **definitions where notes are much longer than definition** (candidates for skew).
- Samples **experimental cmavo** definition + notes to confirm boilerplate.
- Counts **fallback-only definitions by type** (no glosswords), i.e. what we currently embed as definition+notes.

From this you can:

- See which types have long notes and high fallback usage.
- Decide which types should have notes excluded in the fallback path (we already exclude for experimental/obsolete cmavo and gismu).
- Spot other descriptors (e.g. “fu'ivla”, “lujvo”) that might need type-specific rules.

## Implemented: type-aware exclusion of notes

- **Rule**: When there are **no glosswords**, we build embedding text from definition + optionally notes. For types where notes are known to skew embeddings, we **exclude notes**.
- **Types excluded** (notes not used in embedding):  
  `experimental cmavo`, `experimental gismu`, `obsolete cmavo`, `obsolete gismu`.
- **Logic**: `skip_notes_for_embedding_type(type_name)` in `src/background/service.rs`; only the fallback path (no glosswords) is affected.

After running the analysis script, you can extend `skip_notes_for_embedding_type` with more descriptors if you see similar boilerplate (e.g. another “experimental” type).

## Suggested next steps (plan)

1. **Run the analysis script**  
   Run `scripts/analyze_embedding_content.sql` on your DB and review:
   - Which types have the longest notes and highest fallback usage.
   - Whether “experimental” / “obsolete” samples match the boilerplate we excluded.

2. **Widen or narrow excluded types**  
   If other type descriptors show the same kind of noisy notes, add them to `skip_notes_for_embedding_type`. If some experimental types have useful notes, consider a more specific list (e.g. only “experimental cmavo”) or a length cap (e.g. exclude notes when longer than definition).

3. **Optional: cap or truncate notes in fallback**  
   For types that keep notes, you could:
   - Use only the first N characters of notes, or
   - Strip known boilerplate substrings (e.g. “Experimental …”, “Not yet in the official list”) before concatenating, so long repetitive notes don’t dominate.

4. **Re-embed after changes**  
   After changing what goes into the embedding text (e.g. excluding more types’ notes), set `embedding = NULL` for affected definitions so the background job recalculates them (e.g. `UPDATE definitions SET embedding = NULL WHERE …` for the chosen type/conditions).

5. **Tune similarity threshold**  
   If results are too few, try relaxing (e.g. `similarity < 0.5`); if too many irrelevant hits, tighten (e.g. `similarity < 0.35`). You can make this configurable (env var or config) and optionally A/B test.

6. **Optional: stronger model**  
   If you need better semantic quality and can afford 1024-d and more compute, consider switching back to a model like BAAI/bge-m3 and the corresponding migration (dimension + index).

## Files touched

- `scripts/analyze_embedding_content.sql` – DB analysis for embedding content by type.
- `src/background/service.rs` – `skip_notes_for_embedding_type()`, and fallback path uses definition-only for those types (notes excluded).
- `docs/embedding_improvement_plan.md` – this plan.
