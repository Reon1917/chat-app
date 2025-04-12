-- Migration: 04_direct_messaging.sql
-- Description: Adds direct messaging functionality between users
-- Created: 2023-10-15

-- Create direct message conversations table
CREATE TABLE IF NOT EXISTS public.direct_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

-- Set up RLS for direct conversations
ALTER TABLE public.direct_conversations ENABLE ROW LEVEL SECURITY;

-- Create a table to manage participants in direct conversations
CREATE TABLE IF NOT EXISTS public.direct_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.direct_conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, 
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
  UNIQUE(conversation_id, user_id)
);

-- Set up RLS for direct participants
ALTER TABLE public.direct_participants ENABLE ROW LEVEL SECURITY;

-- Users can view conversations they're part of
CREATE POLICY "Users can view conversations they are in" 
  ON public.direct_conversations FOR SELECT 
  USING (
    id IN (
      SELECT conversation_id FROM public.direct_participants WHERE user_id = auth.uid()
    )
  );

-- Users can view participants in their conversations
CREATE POLICY "Users can view participants in their conversations" 
  ON public.direct_participants FOR SELECT 
  USING (
    conversation_id IN (
      SELECT conversation_id FROM public.direct_participants WHERE user_id = auth.uid()
    )
  );

-- Users can join conversations they're invited to (will be controlled by application logic)
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
    conversation_id IN (
      SELECT conversation_id FROM public.direct_participants WHERE user_id = auth.uid()
    )
  );

-- Users can send messages to conversations they're part of
CREATE POLICY "Users can send messages to their conversations" 
  ON public.direct_messages FOR INSERT 
  WITH CHECK (
    sender_id = auth.uid() AND
    conversation_id IN (
      SELECT conversation_id FROM public.direct_participants WHERE user_id = auth.uid()
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
  JOIN public.direct_participants p1 ON c.id = p1.conversation_id AND p1.user_id = user1_id
  JOIN public.direct_participants p2 ON c.id = p2.conversation_id AND p2.user_id = user2_id
  WHERE (
    SELECT COUNT(*) FROM public.direct_participants WHERE conversation_id = c.id
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

-- Enable realtime subscriptions
ALTER publication supabase_realtime ADD TABLE public.direct_conversations;
ALTER publication supabase_realtime ADD TABLE public.direct_participants;
ALTER publication supabase_realtime ADD TABLE public.direct_messages; 