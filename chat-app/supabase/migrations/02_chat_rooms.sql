-- Migration: 02_chat_rooms.sql
-- Description: Adds chat rooms functionality with proper permissions
-- Created: 2023-10-15

-- Create a chat rooms table for multiple chat channels
CREATE TABLE IF NOT EXISTS public.rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  is_private BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

-- Create a relationship table for room members
CREATE TABLE IF NOT EXISTS public.room_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
  UNIQUE(room_id, user_id)
);

-- Set up RLS for rooms
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;

-- Everyone can see public rooms
CREATE POLICY "Public rooms are viewable by everyone" 
  ON public.rooms FOR SELECT 
  USING (is_private = false);

-- Only members can see private rooms
CREATE POLICY "Private rooms are viewable only by members" 
  ON public.rooms FOR SELECT 
  USING (
    is_private = false OR 
    id IN (SELECT room_id FROM public.room_members WHERE user_id = auth.uid())
  );

-- Only creators can update rooms
CREATE POLICY "Users can update their own rooms" 
  ON public.rooms FOR UPDATE 
  USING (created_by = auth.uid());

-- Set up RLS for room members
ALTER TABLE public.room_members ENABLE ROW LEVEL SECURITY;

-- Non-recursive policy for viewing room members
CREATE POLICY "Users can view their own room memberships" 
  ON public.room_members FOR SELECT 
  USING (user_id = auth.uid());

-- Also allow users to see other members in rooms they belong to
CREATE POLICY "Users can see other members in their rooms" 
  ON public.room_members FOR SELECT 
  USING (
    room_id IN (
      SELECT r.id FROM public.rooms r 
      LEFT JOIN public.room_members rm ON r.id = rm.room_id AND rm.user_id = auth.uid()
      WHERE r.is_private = false OR rm.user_id IS NOT NULL OR r.created_by = auth.uid()
    )
  );

-- Allow users to join rooms
CREATE POLICY "Users can join rooms"
  ON public.room_members FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Add room_id to messages table
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS room_id UUID REFERENCES public.rooms(id) ON DELETE CASCADE;

-- Update message policies for room-based access
DROP POLICY IF EXISTS "Users can view all messages" ON public.messages;
CREATE POLICY "Users can view messages in their rooms" 
  ON public.messages FOR SELECT 
  USING (
    room_id IN (
      SELECT id FROM public.rooms WHERE is_private = false
      UNION
      SELECT room_id FROM public.room_members WHERE user_id = auth.uid()
    )
  );

-- Update the message insert policy to check room membership
DROP POLICY IF EXISTS "Users can insert their own messages" ON public.messages;
CREATE POLICY "Users can insert messages in their rooms" 
  ON public.messages FOR INSERT 
  WITH CHECK (
    auth.uid() = user_id AND
    (
      room_id IN (
        SELECT id FROM public.rooms WHERE is_private = false
        UNION
        SELECT room_id FROM public.room_members WHERE user_id = auth.uid()
      )
    )
  );

-- Enable realtime subscriptions for room tables
ALTER publication supabase_realtime ADD TABLE public.rooms;
ALTER publication supabase_realtime ADD TABLE public.room_members; 