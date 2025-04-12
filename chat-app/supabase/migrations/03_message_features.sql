-- Migration: 03_message_features.sql
-- Description: Adds read receipts and typing indicators
-- Created: 2023-10-15

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

-- Users can see who read messages in their rooms
CREATE POLICY "Message reads are viewable by room members" 
  ON public.message_reads FOR SELECT 
  USING (
    message_id IN (
      SELECT id FROM public.messages WHERE room_id IN (
        SELECT room_id FROM public.room_members WHERE user_id = auth.uid()
      )
    )
  );

-- Users can mark messages as read
CREATE POLICY "Users can insert their own message reads" 
  ON public.message_reads FOR INSERT 
  WITH CHECK (
    auth.uid() = user_id AND
    message_id IN (
      SELECT id FROM public.messages WHERE room_id IN (
        SELECT room_id FROM public.room_members WHERE user_id = auth.uid()
      )
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

-- Users can see who's typing in their rooms
CREATE POLICY "Typing indicators are viewable by room members" 
  ON public.typing_indicators FOR SELECT 
  USING (
    room_id IN (
      SELECT room_id FROM public.room_members WHERE user_id = auth.uid()
    )
  );

-- Users can update their own typing status
CREATE POLICY "Users can update their own typing status" 
  ON public.typing_indicators FOR INSERT 
  WITH CHECK (
    auth.uid() = user_id AND
    room_id IN (
      SELECT room_id FROM public.room_members WHERE user_id = auth.uid()
    )
  );

-- Enable realtime subscriptions for new tables
ALTER publication supabase_realtime ADD TABLE public.message_reads;
ALTER publication supabase_realtime ADD TABLE public.typing_indicators; 