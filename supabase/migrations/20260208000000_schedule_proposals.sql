-- Add message_type and metadata columns for schedule proposals
ALTER TABLE messages ADD COLUMN IF NOT EXISTS message_type TEXT DEFAULT 'text';
ALTER TABLE messages ADD COLUMN IF NOT EXISTS metadata JSONB;

-- Add index for finding proposal messages
CREATE INDEX IF NOT EXISTS idx_messages_type ON messages(message_type) WHERE message_type != 'text';

-- Comment explaining the structure
COMMENT ON COLUMN messages.message_type IS 'Type of message: text, schedule_proposal';
COMMENT ON COLUMN messages.metadata IS 'JSON metadata for special message types. For schedule_proposal: {proposed_date, proposed_time, status: pending|accepted|declined, responded_at}';
