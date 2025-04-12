-- Chat App Database Migration Runner
-- Run this script to set up or update your Supabase database schema
-- Last updated: 2023-10-15

-- Note: You can run this entire script at once for a new setup,
-- or run individual migration files when needed.

-- Migration 1: Base schema (messages and profiles)
\i 'migrations/01_base_schema.sql'

-- Migration 2: Chat rooms functionality
\i 'migrations/02_chat_rooms.sql'

-- Migration 3: Message features (read receipts and typing indicators)
\i 'migrations/03_message_features.sql'

-- Migration 4: Direct messaging functionality
\i 'migrations/04_direct_messaging.sql'

-- Note: Migration 5 only needs to be run if you encounter
-- the "infinite recursion detected in policy" error
-- Uncomment this line to run it:
-- \i 'migrations/05_fix_recursive_policy.sql' 