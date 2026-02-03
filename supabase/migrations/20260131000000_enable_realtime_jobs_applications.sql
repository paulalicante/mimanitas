-- Enable realtime for jobs and applications tables
-- so clients can subscribe to INSERT events for notifications
ALTER PUBLICATION supabase_realtime ADD TABLE jobs;
ALTER PUBLICATION supabase_realtime ADD TABLE applications;
