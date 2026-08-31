-- 0013: Row-Level Encryption (RLE) - Schema Contract v1.14 (BREAKING).
-- Sensitive fields move into `enc`: an opaque, client-encrypted envelope
-- (AES-256-GCM, format "v1.<b64 iv>.<b64 ciphertext>", AAD-bound to table:id).
-- The server stores and returns it verbatim and NEVER reads inside it.
--
-- The plaintext columns are DROPPED (destructive): alpha-phase decision
-- 2026-07-02 - no real user data exists; the operator wipes cloud data during
-- the coordinated client+server deploy. Dropping (vs. nulling) makes
-- "DB operators cannot read sensitive data" structural, not conventional.
-- Categories, subcategories and members stay plaintext by design.
-- RLS, triggers, indexes and family_version() reference none of these columns.

alter table public.transactions
  add column if not exists enc text,
  drop column if exists amount,
  drop column if exists description,
  drop column if exists tags;

alter table public.accounts
  add column if not exists enc text,
  drop column if exists name,
  drop column if exists description;

alter table public.entities
  add column if not exists enc text,
  drop column if exists name,
  drop column if exists aliases,
  drop column if exists match_patterns;

alter table public.staged_transactions
  add column if not exists enc text,
  drop column if exists amount,
  drop column if exists description,
  drop column if exists tags,
  drop column if exists source_account,
  drop column if exists source_category,
  drop column if exists source_name,
  drop column if exists source_row;
