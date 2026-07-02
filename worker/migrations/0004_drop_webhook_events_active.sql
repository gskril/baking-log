-- Drop dead webhook columns:
--   * `events` was never read anywhere.
--   * `active` could never become 0 — there is no toggle/update endpoint,
--     only create and delete.
ALTER TABLE webhooks DROP COLUMN events;
ALTER TABLE webhooks DROP COLUMN active;
