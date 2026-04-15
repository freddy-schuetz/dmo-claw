-- Migration 006: MCP Bridge support
-- Adds auth columns to mcp_registry so external MCP servers (bridge templates)
-- can be called with a bearer token or custom Authorization header.
--
-- Note: dmo-claw inlines migrations into setup.sh — this file exists for parity
-- with n8n-claw and as reference documentation. The actual apply path is the
-- MIGRATIONS heredoc in setup.sh.

ALTER TABLE public.mcp_registry
  ADD COLUMN IF NOT EXISTS auth_type text DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS auth_token text;

COMMENT ON COLUMN public.mcp_registry.auth_type IS 'none | bearer | header';
COMMENT ON COLUMN public.mcp_registry.auth_token IS 'Bearer token or full header value (plaintext, service-role access only)';
