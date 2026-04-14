--
-- Knowledge System Migration (Phase 1 + Phase 2) — dmo-claw Multi-User Variant
--
-- Phase 1: Enriched Memory — new columns on memory_long + extended search functions
-- Phase 2: Knowledge Graph — kg_entities + kg_relations + graph traversal
--
-- Difference vs n8n-claw upstream:
--   - All search RPCs carry `filter_user_id text DEFAULT NULL` as LAST parameter
--     with semantics `(filter_user_id IS NULL OR row.user_id IS NULL OR row.user_id = filter_user_id)`
--     ("user-or-org-shared") — matches dmo-claw's existing multi-user scoping.
--   - kg_entities has its own `user_id text NULL` column; relations inherit scope
--     from their endpoints and search_entity_graph filters on EVERY hop to prevent
--     cross-user traversal leaks.
--
-- Note: dmo-claw inlines migrations into setup.sh — this file exists for parity
-- with n8n-claw and as reference documentation. The actual apply path is the
-- MIGRATIONS heredoc in setup.sh.
--
-- Idempotent: can be run multiple times (IF NOT EXISTS / CREATE OR REPLACE).
-- Exception: DROP FUNCTION for search_memory/search_memory_keyword/search_entities
-- (return type or signature changes require DROP before CREATE).
--

-- ============================================================
-- PHASE 1: Enriched Memory
-- ============================================================

-- New columns on memory_long
ALTER TABLE public.memory_long ADD COLUMN IF NOT EXISTS tags text[] DEFAULT '{}';
ALTER TABLE public.memory_long ADD COLUMN IF NOT EXISTS entity_name text;
ALTER TABLE public.memory_long ADD COLUMN IF NOT EXISTS source text;

-- Indexes for new columns
CREATE INDEX IF NOT EXISTS idx_memory_long_entity_name
  ON public.memory_long (entity_name)
  WHERE entity_name IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_memory_long_tags
  ON public.memory_long USING gin (tags)
  WHERE tags != '{}';

-- Extended search function: search_memory
-- DROP required because return type changes (3 new columns) AND signature changes
-- (added filter_entity / filter_tags). Cover all historical signatures:
DROP FUNCTION IF EXISTS public.search_memory(public.vector, double precision, integer, text);
DROP FUNCTION IF EXISTS public.search_memory(public.vector, double precision, integer, text, text);
DROP FUNCTION IF EXISTS public.search_memory(public.vector, double precision, integer, text, text, text[]);
DROP FUNCTION IF EXISTS public.search_memory(public.vector, double precision, integer, text, text, text[], text);

CREATE FUNCTION public.search_memory(
  query_embedding public.vector,
  match_threshold double precision DEFAULT 0.7,
  match_count integer DEFAULT 5,
  filter_category text DEFAULT NULL,
  filter_entity text DEFAULT NULL,
  filter_tags text[] DEFAULT NULL,
  filter_user_id text DEFAULT NULL
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
  source text
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ml.id,
    ml.content,
    ml.category,
    ml.importance,
    1 - (ml.embedding <=> query_embedding) as similarity,
    ml.metadata,
    ml.created_at,
    ml.tags,
    ml.entity_name,
    ml.source
  FROM memory_long ml
  WHERE
    (filter_category IS NULL OR ml.category = filter_category)
    AND (filter_entity IS NULL OR ml.entity_name ILIKE filter_entity)
    AND (filter_tags IS NULL OR ml.tags @> filter_tags)
    AND 1 - (ml.embedding <=> query_embedding) > match_threshold
    AND (ml.expires_at IS NULL OR ml.expires_at > now())
    AND (filter_user_id IS NULL OR ml.user_id IS NULL OR ml.user_id = filter_user_id)
  ORDER BY ml.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

ALTER FUNCTION public.search_memory(public.vector, double precision, integer, text, text, text[], text) OWNER TO postgres;

GRANT ALL ON FUNCTION public.search_memory(public.vector, double precision, integer, text, text, text[], text) TO anon;
GRANT ALL ON FUNCTION public.search_memory(public.vector, double precision, integer, text, text, text[], text) TO authenticated;
GRANT ALL ON FUNCTION public.search_memory(public.vector, double precision, integer, text, text, text[], text) TO service_role;

-- Extended search function: search_memory_keyword
DROP FUNCTION IF EXISTS public.search_memory_keyword(text, integer);
DROP FUNCTION IF EXISTS public.search_memory_keyword(text, integer, text);
DROP FUNCTION IF EXISTS public.search_memory_keyword(text, integer, text, text[]);
DROP FUNCTION IF EXISTS public.search_memory_keyword(text, integer, text, text[], text);

CREATE FUNCTION public.search_memory_keyword(
  search_query text,
  match_count integer DEFAULT 5,
  filter_entity text DEFAULT NULL,
  filter_tags text[] DEFAULT NULL,
  filter_user_id text DEFAULT NULL
) RETURNS TABLE(
  id integer,
  content text,
  category text,
  importance integer,
  metadata jsonb,
  created_at timestamp with time zone,
  tags text[],
  entity_name text,
  source text
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ml.id,
    ml.content,
    ml.category,
    ml.importance,
    ml.metadata,
    ml.created_at,
    ml.tags,
    ml.entity_name,
    ml.source
  FROM memory_long ml
  WHERE
    ml.content ILIKE '%' || search_query || '%'
    AND (filter_entity IS NULL OR ml.entity_name ILIKE filter_entity)
    AND (filter_tags IS NULL OR ml.tags @> filter_tags)
    AND (ml.expires_at IS NULL OR ml.expires_at > now())
    AND (filter_user_id IS NULL OR ml.user_id IS NULL OR ml.user_id = filter_user_id)
  ORDER BY ml.importance DESC, ml.created_at DESC
  LIMIT match_count;
END;
$$;

ALTER FUNCTION public.search_memory_keyword(text, integer, text, text[], text) OWNER TO postgres;

GRANT ALL ON FUNCTION public.search_memory_keyword(text, integer, text, text[], text) TO anon;
GRANT ALL ON FUNCTION public.search_memory_keyword(text, integer, text, text[], text) TO authenticated;
GRANT ALL ON FUNCTION public.search_memory_keyword(text, integer, text, text[], text) TO service_role;


-- ============================================================
-- PHASE 2: Knowledge Graph (multi-user aware)
-- ============================================================

-- Entities table — includes user_id for multi-user scoping
CREATE TABLE IF NOT EXISTS public.kg_entities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  entity_type TEXT,
  summary TEXT,
  metadata JSONB DEFAULT '{}',
  embedding public.vector(1536),
  user_id text,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Belt-and-braces: add user_id if table pre-existed without it
ALTER TABLE public.kg_entities ADD COLUMN IF NOT EXISTS user_id text;

ALTER TABLE public.kg_entities OWNER TO postgres;

-- Relations table — no own user_id, scope inherited from endpoints
CREATE TABLE IF NOT EXISTS public.kg_relations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id UUID REFERENCES public.kg_entities(id) ON DELETE CASCADE,
  target_id UUID REFERENCES public.kg_entities(id) ON DELETE CASCADE,
  relation_type TEXT NOT NULL,
  weight FLOAT DEFAULT 1.0,
  metadata JSONB DEFAULT '{}',
  valid_from TIMESTAMPTZ DEFAULT now(),
  valid_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.kg_relations OWNER TO postgres;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_kg_entities_type ON public.kg_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_kg_entities_name ON public.kg_entities(name);
CREATE INDEX IF NOT EXISTS idx_kg_entities_user_id ON public.kg_entities(user_id);
CREATE INDEX IF NOT EXISTS idx_kg_relations_source ON public.kg_relations(source_id);
CREATE INDEX IF NOT EXISTS idx_kg_relations_target ON public.kg_relations(target_id);
CREATE INDEX IF NOT EXISTS idx_kg_entities_embedding ON public.kg_entities USING hnsw (embedding public.vector_cosine_ops);

-- Grants
GRANT ALL ON TABLE public.kg_entities TO anon;
GRANT ALL ON TABLE public.kg_entities TO authenticated;
GRANT ALL ON TABLE public.kg_entities TO service_role;

GRANT ALL ON TABLE public.kg_relations TO anon;
GRANT ALL ON TABLE public.kg_relations TO authenticated;
GRANT ALL ON TABLE public.kg_relations TO service_role;

-- Semantic entity search — user-scoped
DROP FUNCTION IF EXISTS public.search_entities(public.vector, text, text, double precision, integer);
DROP FUNCTION IF EXISTS public.search_entities(public.vector, text, text, double precision, integer, text);

CREATE FUNCTION public.search_entities(
  query_embedding public.vector DEFAULT NULL,
  search_name text DEFAULT NULL,
  filter_type text DEFAULT NULL,
  match_threshold double precision DEFAULT 0.7,
  match_count integer DEFAULT 10,
  filter_user_id text DEFAULT NULL
) RETURNS TABLE(
  id UUID,
  name TEXT,
  entity_type TEXT,
  summary TEXT,
  metadata JSONB,
  similarity double precision,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.name,
    e.entity_type,
    e.summary,
    e.metadata,
    CASE WHEN query_embedding IS NOT NULL AND e.embedding IS NOT NULL
      THEN 1 - (e.embedding <=> query_embedding)
      ELSE 0.0
    END AS similarity,
    e.created_at
  FROM public.kg_entities e
  WHERE
    (filter_type IS NULL OR e.entity_type = filter_type)
    AND (search_name IS NULL OR e.name ILIKE '%' || search_name || '%')
    AND (
      query_embedding IS NULL
      OR e.embedding IS NULL
      OR 1 - (e.embedding <=> query_embedding) > match_threshold
    )
    AND (filter_user_id IS NULL OR e.user_id IS NULL OR e.user_id = filter_user_id)
  ORDER BY
    CASE WHEN query_embedding IS NOT NULL AND e.embedding IS NOT NULL
      THEN e.embedding <=> query_embedding
      ELSE 0
    END
  LIMIT match_count;
END;
$$;

ALTER FUNCTION public.search_entities(public.vector, text, text, double precision, integer, text) OWNER TO postgres;

GRANT ALL ON FUNCTION public.search_entities(public.vector, text, text, double precision, integer, text) TO anon;
GRANT ALL ON FUNCTION public.search_entities(public.vector, text, text, double precision, integer, text) TO authenticated;
GRANT ALL ON FUNCTION public.search_entities(public.vector, text, text, double precision, integer, text) TO service_role;

-- Graph traversal — user-scoped on EVERY hop (prevents cross-user leakage)
DROP FUNCTION IF EXISTS public.search_entity_graph(UUID, integer);
DROP FUNCTION IF EXISTS public.search_entity_graph(UUID, integer, text);

CREATE FUNCTION public.search_entity_graph(
  start_id UUID,
  max_depth integer DEFAULT 2,
  filter_user_id text DEFAULT NULL
) RETURNS TABLE(
  entity_id UUID,
  name TEXT,
  entity_type TEXT,
  summary TEXT,
  depth integer,
  relation_type TEXT,
  relation_direction TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
  -- Guard: start entity must be visible to the caller's scope
  IF NOT EXISTS (
    SELECT 1 FROM public.kg_entities e
    WHERE e.id = start_id
      AND (filter_user_id IS NULL OR e.user_id IS NULL OR e.user_id = filter_user_id)
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH RECURSIVE graph AS (
    -- Base: direct relations (outgoing + incoming), target must be in-scope
    SELECT * FROM (
      SELECT r.target_id AS eid, 1 AS d, r.relation_type AS rtype, 'outgoing'::text AS dir
      FROM public.kg_relations r
      JOIN public.kg_entities te ON te.id = r.target_id
      WHERE r.source_id = start_id
        AND (r.valid_until IS NULL OR r.valid_until > now())
        AND (filter_user_id IS NULL OR te.user_id IS NULL OR te.user_id = filter_user_id)
      UNION ALL
      SELECT r.source_id, 1, r.relation_type, 'incoming'::text
      FROM public.kg_relations r
      JOIN public.kg_entities se ON se.id = r.source_id
      WHERE r.target_id = start_id
        AND (r.valid_until IS NULL OR r.valid_until > now())
        AND (filter_user_id IS NULL OR se.user_id IS NULL OR se.user_id = filter_user_id)
    ) base
    UNION ALL
    -- Recursive: multi-hop, scope-check the NEW endpoint on every hop
    SELECT
      CASE WHEN r.source_id = g.eid THEN r.target_id ELSE r.source_id END AS eid,
      g.d + 1 AS d,
      r.relation_type AS rtype,
      CASE WHEN r.source_id = g.eid THEN 'outgoing'::text ELSE 'incoming'::text END AS dir
    FROM public.kg_relations r
    JOIN graph g ON (r.source_id = g.eid OR r.target_id = g.eid)
    JOIN public.kg_entities ne
      ON ne.id = CASE WHEN r.source_id = g.eid THEN r.target_id ELSE r.source_id END
    WHERE g.d < max_depth
      AND (r.valid_until IS NULL OR r.valid_until > now())
      AND (filter_user_id IS NULL OR ne.user_id IS NULL OR ne.user_id = filter_user_id)
  )
  SELECT DISTINCT ON (g.eid)
    g.eid AS entity_id,
    e.name,
    e.entity_type,
    e.summary,
    g.d AS depth,
    g.rtype AS relation_type,
    g.dir AS relation_direction
  FROM graph g
  JOIN public.kg_entities e ON e.id = g.eid
  WHERE (filter_user_id IS NULL OR e.user_id IS NULL OR e.user_id = filter_user_id)
  ORDER BY g.eid, g.d;
END;
$$;

ALTER FUNCTION public.search_entity_graph(UUID, integer, text) OWNER TO postgres;

GRANT ALL ON FUNCTION public.search_entity_graph(UUID, integer, text) TO anon;
GRANT ALL ON FUNCTION public.search_entity_graph(UUID, integer, text) TO authenticated;
GRANT ALL ON FUNCTION public.search_entity_graph(UUID, integer, text) TO service_role;
