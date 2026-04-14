--
-- Hybrid Search Migration (v1.2.0) — dmo-claw Multi-User Variant
--
-- Adds: tsvector full-text search, RRF hybrid search RPC, time decay scoring
-- Requires: 004_knowledge.sql (enriched memory columns: tags, entity_name, source)
--
-- Difference vs n8n-claw upstream:
--   `hybrid_search_memory` takes `filter_user_id text` as a MANDATORY parameter
--   (no DEFAULT). Every caller must pass it explicitly — NULL is allowed for
--   deliberate org-wide scope, but omitting the parameter raises a Postgres
--   error. This prevents accidental cross-user leaks from a sub-workflow bug.
--
-- Note: dmo-claw inlines migrations into setup.sh — this file exists for parity
-- with n8n-claw and as reference documentation. The actual apply path is the
-- MIGRATIONS heredoc in setup.sh.
--
-- Idempotent: can be run multiple times (IF NOT EXISTS / CREATE OR REPLACE / DROP before CREATE).
--

-- ============================================================
-- 1. EXTENSION: unaccent (multi-language accent/umlaut normalization)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS unaccent;

-- Immutable wrapper for unaccent(): Postgres requires IMMUTABLE expressions
-- for GENERATED ALWAYS AS ... STORED columns. The built-in unaccent() is
-- marked STABLE (because it reads the unaccent dictionary), but the dictionary
-- never changes at runtime, so an IMMUTABLE wrapper is safe and widely used.
CREATE OR REPLACE FUNCTION public.immutable_unaccent(text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
AS $func$
  SELECT public.unaccent('public.unaccent', $1)
$func$;


-- ============================================================
-- 2. GENERATED tsvector COLUMN on memory_long
-- ============================================================
-- Combines content + entity_name for full-text search.
-- Uses 'simple' config (no language-specific stemming) + immutable_unaccent for
-- language-agnostic matching: München ↔ muenchen, résumé ↔ resume.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'memory_long'
      AND column_name = 'search_vector'
  ) THEN
    ALTER TABLE public.memory_long
      ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (
        to_tsvector('simple', public.immutable_unaccent(coalesce(content, '') || ' ' || coalesce(entity_name, '')))
      ) STORED;
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_memory_long_search_vector
  ON public.memory_long USING gin (search_vector);


-- ============================================================
-- 3. RPC: hybrid_search_memory (multi-user, filter_user_id MANDATORY)
-- ============================================================
-- Three-branch Reciprocal Rank Fusion (RRF) with optional time decay.
--
-- Branch 1: Semantic — pgvector cosine distance (top 50)
-- Branch 2: Fulltext — tsvector ts_rank_cd cover-density ranking (top 50)
-- Branch 3: Entity  — direct ILIKE match on entity_name (top 50)
--
-- RRF formula: score = Σ 1/(k + rank) across all branches where a row appears.
-- k=60 is the Cormack et al. (2009) default, widely used in RAG systems.
--
-- Time decay: exponential half-life scaled by importance.
--   half_life = 90 + importance * 20 (range: 110–290 days)
--   factor = 0.5 ^ (days_old / half_life)
--   Exempt categories (contact, preference, decision) always get factor 1.0.
--   Disabled entirely when use_time_decay = false.
--
-- Multi-user scoping:
--   filter_user_id is a MANDATORY parameter (no DEFAULT). Pass NULL explicitly
--   for org-wide scope. `(filter_user_id IS NULL OR ml.user_id IS NULL OR
--   ml.user_id = filter_user_id)` — matches dmo-claw's user-or-org semantics.

DROP FUNCTION IF EXISTS public.hybrid_search_memory(
  public.vector, text, integer, text, text, text[], boolean, integer
);
DROP FUNCTION IF EXISTS public.hybrid_search_memory(
  public.vector, text, integer, text, text, text[], boolean, integer, text
);

CREATE FUNCTION public.hybrid_search_memory(
  query_embedding public.vector,
  query_text text,
  match_count integer,
  filter_category text,
  filter_entity text,
  filter_tags text[],
  use_time_decay boolean,
  rrf_k integer,
  filter_user_id text
) RETURNS TABLE(
  id integer,
  content text,
  category text,
  importance integer,
  similarity double precision,
  metadata jsonb,
  created_at timestamp with time zone,
  tags text[],
  entity_name text,
  source text,
  rrf_score double precision,
  decay_factor double precision
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  WITH
  -- Pre-filter: apply user filters once, reuse across all branches
  filtered AS (
    SELECT ml.*
    FROM public.memory_long ml
    WHERE (filter_category IS NULL OR ml.category = filter_category)
      AND (filter_entity   IS NULL OR ml.entity_name ILIKE filter_entity)
      AND (filter_tags     IS NULL OR ml.tags @> filter_tags)
      AND (ml.expires_at   IS NULL OR ml.expires_at > now())
      AND (filter_user_id  IS NULL OR ml.user_id IS NULL OR ml.user_id = filter_user_id)
  ),

  -- Branch 1: Semantic (pgvector cosine distance, top 50)
  semantic_hits AS (
    SELECT f.id,
      ROW_NUMBER() OVER (ORDER BY f.embedding <=> query_embedding) AS rnk
    FROM filtered f
    WHERE query_embedding IS NOT NULL
      AND f.embedding IS NOT NULL
    ORDER BY f.embedding <=> query_embedding
    LIMIT 50
  ),

  -- Branch 2: Fulltext (tsvector + ts_rank_cd cover-density, top 50)
  fulltext_hits AS (
    SELECT f.id,
      ROW_NUMBER() OVER (
        ORDER BY ts_rank_cd(f.search_vector, plainto_tsquery('simple', unaccent(query_text))) DESC
      ) AS rnk
    FROM filtered f
    WHERE query_text IS NOT NULL
      AND f.search_vector @@ plainto_tsquery('simple', unaccent(query_text))
    ORDER BY ts_rank_cd(f.search_vector, plainto_tsquery('simple', unaccent(query_text))) DESC
    LIMIT 50
  ),

  -- Branch 3: Entity direct match (eigennamen boost, top 50)
  entity_hits AS (
    SELECT f.id,
      ROW_NUMBER() OVER (ORDER BY f.importance DESC, f.created_at DESC) AS rnk
    FROM filtered f
    WHERE query_text IS NOT NULL
      AND f.entity_name IS NOT NULL
      AND f.entity_name ILIKE '%' || query_text || '%'
    LIMIT 50
  ),

  -- RRF fusion: combine all branches
  fused AS (
    SELECT x.id, SUM(x.weight) AS rrf_score
    FROM (
      SELECT sh.id, 1.0 / (rrf_k + sh.rnk) AS weight FROM semantic_hits sh
      UNION ALL
      SELECT fh.id, 1.0 / (rrf_k + fh.rnk) AS weight FROM fulltext_hits fh
      UNION ALL
      SELECT eh.id, 1.0 / (rrf_k + eh.rnk) AS weight FROM entity_hits eh
    ) x
    GROUP BY x.id
  )

  SELECT
    f.id,
    f.content,
    f.category,
    f.importance,
    CASE
      WHEN query_embedding IS NOT NULL AND f.embedding IS NOT NULL
      THEN 1 - (f.embedding <=> query_embedding)
      ELSE 0.0
    END AS similarity,
    f.metadata,
    f.created_at,
    f.tags,
    f.entity_name,
    f.source,
    (fused.rrf_score * decay.factor)::double precision AS rrf_score,
    decay.factor::double precision AS decay_factor
  FROM fused
  JOIN filtered f ON f.id = fused.id
  CROSS JOIN LATERAL (
    SELECT CASE
      WHEN NOT use_time_decay THEN 1.0
      WHEN f.category IN ('contact', 'preference', 'decision') THEN 1.0
      ELSE POWER(
        0.5,
        EXTRACT(EPOCH FROM (now() - f.created_at)) / 86400.0
        / (90.0 + f.importance * 20.0)
      )
    END AS factor
  ) decay
  ORDER BY fused.rrf_score * decay.factor DESC
  LIMIT match_count;
END;
$$;

ALTER FUNCTION public.hybrid_search_memory(
  public.vector, text, integer, text, text, text[], boolean, integer, text
) OWNER TO postgres;

GRANT ALL ON FUNCTION public.hybrid_search_memory(
  public.vector, text, integer, text, text, text[], boolean, integer, text
) TO anon;

GRANT ALL ON FUNCTION public.hybrid_search_memory(
  public.vector, text, integer, text, text, text[], boolean, integer, text
) TO authenticated;

GRANT ALL ON FUNCTION public.hybrid_search_memory(
  public.vector, text, integer, text, text, text[], boolean, integer, text
) TO service_role;
