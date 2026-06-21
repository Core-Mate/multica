DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'autopilot_subscriber'::regclass
      AND conname = 'autopilot_subscriber_autopilot_id_fkey'
  ) THEN
    ALTER TABLE autopilot_subscriber
      ADD CONSTRAINT autopilot_subscriber_autopilot_id_fkey
      FOREIGN KEY (autopilot_id) REFERENCES autopilot(id) ON DELETE CASCADE
      NOT VALID;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'comment'::regclass
      AND conname = 'comment_source_task_id_fkey'
  ) THEN
    ALTER TABLE comment
      ADD CONSTRAINT comment_source_task_id_fkey
      FOREIGN KEY (source_task_id) REFERENCES agent_task_queue(id) ON DELETE SET NULL
      NOT VALID;
  END IF;
END $$;
