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

-- FIXED POLICY: Instead of recursively checking room_members, we'll directly allow users to see rooms where they're a member
CREATE POLICY "Users can view rooms they are members of" 
  ON public.room_members FOR SELECT 
  USING (user_id = auth.uid());

-- ALTERNATIVE POLICY: If users should see all members in rooms they're in
CREATE POLICY "Users can view other members in their rooms" 
  ON public.room_members FOR SELECT 
  USING (
    room_id IN (
      SELECT room_id FROM public.rooms WHERE 
        is_private = false OR
        created_by = auth.uid() OR
        room_id IN (SELECT room_id FROM public.room_members WHERE user_id = auth.uid())
    )
  );

-- Allow users to join rooms (this will be controlled by application logic)
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

-- Enable realtime subscriptions for all relevant tables
ALTER publication supabase_realtime ADD TABLE public.rooms;
ALTER publication supabase_realtime ADD TABLE public.room_members;
ALTER publication supabase_realtime ADD TABLE public.message_reads;
ALTER publication supabase_realtime ADD TABLE public.typing_indicators; 