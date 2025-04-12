-- Migration: 05_fix_recursive_policy.sql
-- Description: Fixes the infinite recursion error in room_members policy
-- Created: 2023-10-15

-- This migration only needs to be run if you encounter the following error:
-- "Database error: infinite recursion detected in policy for relation 'room_members'"

-- Drop any potentially problematic recursive policies
DROP POLICY IF EXISTS "Room members are viewable by other members" ON public.room_members;
DROP POLICY IF EXISTS "Users can view other members in their rooms" ON public.room_members;
DROP POLICY IF EXISTS "Users can view rooms they are members of" ON public.room_members;

-- Create a simple policy that allows users to see their own memberships
CREATE POLICY "Users can view their own room memberships" 
  ON public.room_members FOR SELECT 
  USING (user_id = auth.uid());

-- Add a policy so users can see other members in rooms they're in
CREATE POLICY "Users can see other members in their rooms" 
  ON public.room_members FOR SELECT 
  USING (
    room_id IN (
      SELECT r.id FROM public.rooms r 
      LEFT JOIN public.room_members rm ON r.id = rm.room_id AND rm.user_id = auth.uid()
      WHERE r.is_private = false OR rm.user_id IS NOT NULL OR r.created_by = auth.uid()
    )
  ); 