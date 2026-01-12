ALTER TABLE user_notifications
ADD COLUMN email_sent TIMESTAMP;

CREATE INDEX idx_notifications_pending_email 
ON user_notifications(email_sent) 
WHERE email_sent IS NULL;