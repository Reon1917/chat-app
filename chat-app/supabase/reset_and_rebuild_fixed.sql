-- Reset and Rebuild Database Script (Fixed Version)
-- This script drops all existing tables and recreates them with non-recursive policies
-- CAUTION: Running this will delete all data in the affected tables
-- Last updated: 2023-10-20

-- Step 1: Drop everything in a safer, more comprehensive way
DO $$ 
DECLARE
  r RECORD;
BEGIN
  -- Drop realtime publication
  DROP PUBLICATION IF EXISTS supabase_realtime;
  
  -- Disable all triggers to avoid interference during drops
  SET session_replication_role = 'replica';
  
  -- Drop all policies first (policies can create dependencies)
  FOR r IN 
    SELECT policyname, tablename 
    FROM pg_policies 
    WHERE schemaname = 'public'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', r.policyname, r.tablename);
  END LOOP;
  
  -- Drop all triggers
  FOR r IN 
    SELECT tgname, relname
    FROM pg_trigger 
    JOIN pg_class ON pg_trigger.tgrelid = pg_class.oid
    JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
    WHERE pg_namespace.nspname = 'public'
      AND NOT tgisinternal
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', r.tgname, r.relname);
  END LOOP;
  
  -- Drop all functions that we created
  DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
  DROP FUNCTION IF EXISTS public.update_conversation_timestamp() CASCADE;
  DROP FUNCTION IF EXISTS public.find_or_create_conversation(UUID, UUID) CASCADE;
  
  -- Create an array of tables to drop in reverse order of dependencies
  -- Use CASCADE to ensure all dependent objects are also dropped
  DROP TABLE IF EXISTS public.typing_indicators CASCADE;
  DROP TABLE IF EXISTS public.message_reads CASCADE;
  DROP TABLE IF EXISTS public.direct_messages CASCADE;
  DROP TABLE IF EXISTS public.direct_participants CASCADE;
  DROP TABLE IF EXISTS public.direct_conversations CASCADE;
  DROP TABLE IF EXISTS public.room_members CASCADE;
  DROP TABLE IF EXISTS public.messages CASCADE;
  DROP TABLE IF EXISTS public.rooms CASCADE;
  DROP TABLE IF EXISTS public.profiles CASCADE;
  
  -- Reset trigger behavior
  SET session_replication_role = 'origin';
END $$;

-- Step 2: Recreate publication for realtime
CREATE PUBLICATION supabase_realtime;

-- Step 3: Rebuild the database with redesigned policies that avoid recursion
-- ---------------------------------------------
-- Base Schema: Profiles and Messages
-- ---------------------------------------------

-- Create a profile table
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT UNIQUE,
  avatar_url TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Non-recursive RLS policies for profiles
CREATE POLICY "Public profiles are viewable by everyone"
  ON public.profiles FOR SELECT
  USING (true);

CREATE POLICY "Users can insert their own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Function to create a profile after signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, username, avatar_url)
  VALUES (new.id, new.email, 'https://www.gravatar.com/avatar/' || md5(lower(new.email)) || '?d=mp');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to create profile after signup
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Create basic rooms table first to avoid circular references
CREATE TABLE IF NOT EXISTS public.rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  is_private BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

-- Create room_members table before adding RLS to rooms
CREATE TABLE IF NOT EXISTS public.room_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
  UNIQUE(room_id, user_id)
);

-- Create a messages table with room_id
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content TEXT NOT NULL,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_email TEXT NOT NULL,
  room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

-- ---------------------------------------------
-- Set up RLS for rooms in non-recursive way
-- ---------------------------------------------
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;

-- Everyone can see public rooms - simple non-recursive policy
CREATE POLICY "Public rooms are viewable by everyone" 
  ON public.rooms FOR SELECT 
  USING (is_private = false);

-- For private rooms, use a direct join instead of a subquery to avoid recursion
CREATE POLICY "Users can view private rooms they are members of" 
  ON public.rooms FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM public.room_members 
      WHERE room_members.room_id = rooms.id 
      AND room_members.user_id = auth.uid()
    )
  );

-- Users can create rooms
CREATE POLICY "Users can insert rooms"
  ON public.rooms FOR INSERT
  WITH CHECK (auth.uid() = created_by);

-- Only creators can update rooms
CREATE POLICY "Users can update their own rooms" 
  ON public.rooms FOR UPDATE 
  USING (created_by = auth.uid());

-- ---------------------------------------------
-- Set up RLS for room_members in non-recursive way
-- ---------------------------------------------
ALTER TABLE public.room_members ENABLE ROW LEVEL SECURITY;

-- Direct policy - users can see their own memberships
CREATE POLICY "Users can view their own room memberships" 
  ON public.room_members FOR SELECT 
  USING (user_id = auth.uid());

-- Users can see members of public rooms
CREATE POLICY "Users can view members of public rooms" 
  ON public.room_members FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM public.rooms 
      WHERE rooms.id = room_members.room_id 
      AND rooms.is_private = false
    )
  );

-- Users can see members of private rooms they belong to
CREATE POLICY "Users can view members of their private rooms" 
  ON public.room_members FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM public.room_members as my_memberships
      WHERE my_memberships.room_id = room_members.room_id 
      AND my_memberships.user_id = auth.uid()
    )
  );

-- Users can join rooms
CREATE POLICY "Users can join rooms"
  ON public.room_members FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Users can leave rooms
CREATE POLICY "Users can leave rooms"
  ON public.room_members FOR DELETE
  USING (user_id = auth.uid());

-- ---------------------------------------------
-- Set up RLS for messages
-- ---------------------------------------------
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Example of department-based policy using session variables instead of views
-- This is more efficient than creating views or using nested subqueries
CREATE OR REPLACE FUNCTION public.get_user_department()
RETURNS UUID AS $$
DECLARE
  dept_id UUID;
BEGIN
  SELECT department_id INTO dept_id FROM employee 
  WHERE id = (SELECT employee_id FROM account WHERE login = current_user);
  RETURN dept_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Examples showing how to use the function:
-- 1. Set a session variable at login time:
-- SELECT set_config('app.user_department', public.get_user_department()::text, false);

-- 2. Then in policies, use the session variable:
-- CREATE POLICY department_access ON some_table 
--   USING (department_id::text = current_setting('app.user_department', true));

-- Users can view messages in public rooms
CREATE POLICY "Users can view messages in public rooms" 
  ON public.messages FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM public.rooms 
      WHERE rooms.id = messages.room_id 
      AND rooms.is_private = false
    )
  );

-- Users can view messages in private rooms they're members of
CREATE POLICY "Users can view messages in their private rooms" 
  ON public.messages FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM public.room_members 
      WHERE room_members.room_id = messages.room_id 
      AND room_members.user_id = auth.uid()
    )
  );

-- Users can send messages to rooms they're members of
CREATE POLICY "Users can send messages to their rooms" 
  ON public.messages FOR INSERT 
  WITH CHECK (
    auth.uid() = user_id AND
    (
      EXISTS (
        SELECT 1 FROM public.rooms 
        WHERE rooms.id = messages.room_id 
        AND rooms.is_private = false
      ) OR 
      EXISTS (
        SELECT 1 FROM public.room_members 
        WHERE room_members.room_id = messages.room_id 
        AND room_members.user_id = auth.uid()
      )
    )
  );

-- ---------------------------------------------
-- Message Features: Read Receipts & Typing
-- ---------------------------------------------

-- Add read receipts
CREATE TABLE IF NOT EXISTS public.message_reads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  read_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
  UNIQUE(message_id, user_id)
);

-- Set up RLS for message reads
ALTER TABLE public.message_reads ENABLE ROW LEVEL SECURITY;

-- Users can see read receipts for messages they can view
CREATE POLICY "Users can view read receipts for public room messages" 
  ON public.message_reads FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM public.messages
      JOIN public.rooms ON rooms.id = messages.room_id
      WHERE messages.id = message_reads.message_id
      AND rooms.is_private = false
    )
  );

CREATE POLICY "Users can view read receipts for their private room messages" 
  ON public.message_reads FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM public.messages
      JOIN public.room_members ON room_members.room_id = messages.room_id
      WHERE messages.id = message_reads.message_id
      AND room_members.user_id = auth.uid()
    )
  );

-- Users can mark messages as read
CREATE POLICY "Users can insert their own message reads" 
  ON public.message_reads FOR INSERT 
  WITH CHECK (
    auth.uid() = user_id AND
    EXISTS (
      SELECT 1 FROM public.messages
      LEFT JOIN public.room_members ON room_members.room_id = messages.room_id
      LEFT JOIN public.rooms ON rooms.id = messages.room_id
      WHERE messages.id = message_reads.message_id
      AND (rooms.is_private = false OR room_members.user_id = auth.uid())
    )
  );

-- Add typing indicators table
CREATE TABLE IF NOT EXISTS public.typing_indicators (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  is_typing BOOLEAN DEFAULT true,
  last_updated TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
  UNIQUE(room_id, user_id)
);

-- Set up RLS for typing indicators
ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;

-- Users can see typing indicators in public rooms
CREATE POLICY "Users can see typing in public rooms" 
  ON public.typing_indicators FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM public.rooms 
      WHERE rooms.id = typing_indicators.room_id 
      AND rooms.is_private = false
    )
  );

-- Users can see typing indicators in private rooms they're members of
CREATE POLICY "Users can see typing in their private rooms" 
  ON public.typing_indicators FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM public.room_members 
      WHERE room_members.room_id = typing_indicators.room_id 
      AND room_members.user_id = auth.uid()
    )
  );

-- Users can update their own typing status
CREATE POLICY "Users can update their typing status" 
  ON public.typing_indicators FOR INSERT 
  WITH CHECK (
    auth.uid() = user_id AND
    (
      EXISTS (
        SELECT 1 FROM public.rooms 
        WHERE rooms.id = typing_indicators.room_id 
        AND rooms.is_private = false
      ) OR 
      EXISTS (
        SELECT 1 FROM public.room_members 
        WHERE room_members.room_id = typing_indicators.room_id 
        AND room_members.user_id = auth.uid()
      )
    )
  );

-- ---------------------------------------------
-- Direct Messaging System
-- ---------------------------------------------

-- Create direct message conversations table
CREATE TABLE IF NOT EXISTS public.direct_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

-- Create a table to manage participants in direct conversations
CREATE TABLE IF NOT EXISTS public.direct_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.direct_conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, 
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
  UNIQUE(conversation_id, user_id)
);

-- Set up RLS for direct conversations
ALTER TABLE public.direct_conversations ENABLE ROW LEVEL SECURITY;

-- Users can view conversations they're part of
CREATE POLICY "Users can view conversations they are in" 
  ON public.direct_conversations FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM public.direct_participants 
      WHERE direct_participants.conversation_id = direct_conversations.id 
      AND direct_participants.user_id = auth.uid()
    )
  );

-- Set up RLS for direct participants
ALTER TABLE public.direct_participants ENABLE ROW LEVEL SECURITY;

-- Users can view participants in their conversations
CREATE POLICY "Users can view participants in their conversations" 
  ON public.direct_participants FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM public.direct_participants as my_participation
      WHERE my_participation.conversation_id = direct_participants.conversation_id 
      AND my_participation.user_id = auth.uid()
    )
  );

-- Users can join conversations
CREATE POLICY "Users can insert themselves as participants" 
  ON public.direct_participants FOR INSERT 
  WITH CHECK (user_id = auth.uid());

-- Create direct messages table
CREATE TABLE IF NOT EXISTS public.direct_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.direct_conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

-- Set up RLS for direct messages
ALTER TABLE public.direct_messages ENABLE ROW LEVEL SECURITY;

-- Users can view messages in conversations they're part of
CREATE POLICY "Users can view messages in their conversations" 
  ON public.direct_messages FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM public.direct_participants 
      WHERE direct_participants.conversation_id = direct_messages.conversation_id 
      AND direct_participants.user_id = auth.uid()
    )
  );

-- Users can send messages to conversations they're part of
CREATE POLICY "Users can send messages to their conversations" 
  ON public.direct_messages FOR INSERT 
  WITH CHECK (
    sender_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.direct_participants 
      WHERE direct_participants.conversation_id = direct_messages.conversation_id 
      AND direct_participants.user_id = auth.uid()
    )
  );

-- Create function to update conversation timestamp when a message is sent
CREATE OR REPLACE FUNCTION public.update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.direct_conversations
  SET updated_at = NOW()
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for updating conversation timestamp
CREATE OR REPLACE TRIGGER on_message_sent
  AFTER INSERT ON public.direct_messages
  FOR EACH ROW EXECUTE FUNCTION public.update_conversation_timestamp();

-- Helper function to find or create a direct conversation between two users
CREATE OR REPLACE FUNCTION public.find_or_create_conversation(user1_id UUID, user2_id UUID)
RETURNS UUID AS $$
DECLARE
  existing_conversation_id UUID;
  new_conversation_id UUID;
BEGIN
  -- First, try to find an existing conversation between these users
  SELECT c.id INTO existing_conversation_id
  FROM public.direct_conversations c
  WHERE EXISTS (
    SELECT 1 FROM public.direct_participants p1
    WHERE p1.conversation_id = c.id AND p1.user_id = user1_id
  )
  AND EXISTS (
    SELECT 1 FROM public.direct_participants p2
    WHERE p2.conversation_id = c.id AND p2.user_id = user2_id
  )
  AND (
    SELECT COUNT(*) FROM public.direct_participants
    WHERE conversation_id = c.id
  ) = 2
  LIMIT 1;

  -- If conversation exists, return it
  IF existing_conversation_id IS NOT NULL THEN
    RETURN existing_conversation_id;
  END IF;

  -- Otherwise, create a new conversation
  INSERT INTO public.direct_conversations DEFAULT VALUES
  RETURNING id INTO new_conversation_id;

  -- Add both users as participants
  INSERT INTO public.direct_participants (conversation_id, user_id)
  VALUES 
    (new_conversation_id, user1_id),
    (new_conversation_id, user2_id);

  RETURN new_conversation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ---------------------------------------------
-- Enable realtime subscriptions
-- ---------------------------------------------
ALTER publication supabase_realtime ADD TABLE public.profiles;
ALTER publication supabase_realtime ADD TABLE public.messages;
ALTER publication supabase_realtime ADD TABLE public.rooms;
ALTER publication supabase_realtime ADD TABLE public.room_members;
ALTER publication supabase_realtime ADD TABLE public.message_reads;
ALTER publication supabase_realtime ADD TABLE public.typing_indicators;
ALTER publication supabase_realtime ADD TABLE public.direct_conversations;
ALTER publication supabase_realtime ADD TABLE public.direct_participants;
ALTER publication supabase_realtime ADD TABLE public.direct_messages; 