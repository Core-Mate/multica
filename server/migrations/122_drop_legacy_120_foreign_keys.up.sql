-- Migration 120 originally shipped with database FKs, but the migration was
-- later corrected to keep these relationships application-managed. Databases
-- that already applied the first version will not replay 120, so remove the
-- legacy constraints explicitly.
ALTER TABLE autopilot_subscriber
  DROP CONSTRAINT IF EXISTS autopilot_subscriber_autopilot_id_fkey;

ALTER TABLE comment
  DROP CONSTRAINT IF EXISTS comment_source_task_id_fkey;
