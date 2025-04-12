'use client'

import { useState, useEffect, useRef } from 'react'
import { User } from '@supabase/supabase-js'
import { createClient } from '../utils/supabase-browser'
import { z } from 'zod'
import { createErrorWithHelp } from '../utils/error-handler'

// Zod schema for Room
const RoomSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  description: z.string().optional(),
  is_private: z.boolean(),
  created_at: z.string()
})

// Zod schema for Message
const MessageSchema = z.object({
  id: z.string().uuid(),
  content: z.string(),
  created_at: z.string(),
  user_id: z.string().uuid(),
  user_email: z.string().email().optional(),
  room_id: z.string().uuid().optional()
})

interface Message {
  id: string
  content: string
  created_at: string
  user_id: string
  user_email: string
  room_id?: string
}

interface Room {
  id: string
  name: string
  description: string
  is_private: boolean
}

interface ChatInterfaceProps {
  user: User
}

export default function ChatInterface({ user }: ChatInterfaceProps) {
  const [messages, setMessages] = useState<Message[]>([])
  const [newMessage, setNewMessage] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [rooms, setRooms] = useState<Room[]>([])
  const [currentRoom, setCurrentRoom] = useState<Room | null>(null)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const supabase = createClient()

  // Fetch or create a default room
  useEffect(() => {
    const initializeRooms = async () => {
      try {
        setError(null)
        
        // First check if any rooms exist
        const { data: existingRooms, error: roomsError } = await supabase
          .from('rooms')
          .select('*')
          .order('created_at', { ascending: true })
        
        if (roomsError) {
          console.error('Error fetching rooms:', roomsError)
          setError(createErrorWithHelp(roomsError))
          return
        }
        
        if (existingRooms && existingRooms.length > 0) {
          try {
            // Validate room data
            const validatedRooms = existingRooms.map(room => {
              try {
                return RoomSchema.parse(room)
              } catch (parseError) {
                console.warn('Room validation error:', parseError)
                // Provide defaults for missing fields
                return {
                  id: room.id || '',
                  name: room.name || 'Unnamed Room',
                  description: room.description || '',
                  is_private: room.is_private || false,
                  created_at: room.created_at || new Date().toISOString()
                }
              }
            })
            setRooms(validatedRooms)
            setCurrentRoom(validatedRooms[0])
          } catch (validationError) {
            console.error('Room validation error:', validationError)
            setError('Data validation error')
          }
        } else {
          // Create a default room if none exists
          try {
            const { data: newRoom, error: createError } = await supabase
              .from('rooms')
              .insert({
                name: 'General',
                description: 'General chat room',
                created_by: user.id,
                is_private: false
              })
              .select()
              .single()
            
            if (createError) {
              console.error('Error creating room:', createError)
              setError('Failed to create default room: ' + createError.message)
              return
            }
            
            if (!newRoom) {
              setError('Failed to create room - no data returned')
              return
            }
            
            // Join the room
            const { error: joinError } = await supabase
              .from('room_members')
              .insert({
                room_id: newRoom.id,
                user_id: user.id
              })
              
            if (joinError) {
              console.error('Error joining room:', joinError)
              setError('Failed to join room: ' + joinError.message)
              return
            }
            
            setRooms([newRoom])
            setCurrentRoom(newRoom)
          } catch (createError: any) {
            console.error('Error in room creation process:', createError)
            setError('Unexpected error creating room: ' + (createError.message || 'Unknown error'))
          }
        }
      } catch (error: any) {
        console.error('Error initializing rooms:', error)
        setError(createErrorWithHelp(error))
      } finally {
        setLoading(false)
      }
    }
    
    initializeRooms()
  }, [user.id])

  // Fetch messages when component mounts and when current room changes
  useEffect(() => {
    if (currentRoom) {
      fetchMessages()
    }
  }, [currentRoom])
  
  // Set up real-time subscription
  useEffect(() => {
    if (!currentRoom) return
    
    const channel = supabase
      .channel('public:messages')
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'messages',
          filter: `room_id=eq.${currentRoom.id}`
        },
        (payload) => {
          const newMessage = payload.new as Message
          setMessages((current) => [...current, newMessage])
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [currentRoom])

  // Scroll to bottom whenever messages change
  useEffect(() => {
    scrollToBottom()
  }, [messages])

  const fetchMessages = async () => {
    if (!currentRoom) return
    
    try {
      setLoading(true)
      setError(null)
      
      const { data, error } = await supabase
        .from('messages')
        .select('*')
        .eq('room_id', currentRoom.id)
        .order('created_at', { ascending: true })
      
      if (error) {
        throw error
      }
      
      if (data) {
        try {
          // Validate message data
          const validatedMessages = data.map(message => {
            try {
              return MessageSchema.parse(message)
            } catch (parseError) {
              console.warn('Message validation error:', parseError)
              // Provide sensible defaults
              return {
                id: message.id || '',
                content: message.content || '',
                created_at: message.created_at || new Date().toISOString(),
                user_id: message.user_id || '',
                user_email: message.user_email || 'unknown@example.com',
                room_id: message.room_id || currentRoom.id
              }
            }
          })
          setMessages(validatedMessages)
        } catch (validationError) {
          console.error('Message validation error:', validationError)
          setError('Message data validation error')
        }
      } else {
        setMessages([])
      }
    } catch (error: any) {
      console.error('Error fetching messages:', error)
      setError(createErrorWithHelp(error))
    } finally {
      setLoading(false)
    }
  }

  const sendMessage = async (e: React.FormEvent) => {
    e.preventDefault()
    
    if (!newMessage.trim() || !currentRoom) return
    
    try {
      setError(null)
      const { error } = await supabase
        .from('messages')
        .insert({
          content: newMessage.trim(),
          user_id: user.id,
          user_email: user.email,
          room_id: currentRoom.id
        })
      
      if (error) {
        throw error
      }
      
      setNewMessage('')
    } catch (error: any) {
      console.error('Error sending message:', error)
      setError(createErrorWithHelp(error))
    }
  }

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }

  const formatDate = (dateString: string) => {
    const date = new Date(dateString)
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  }

  // Show user's own ID for sharing
  const getUserIdDisplay = () => {
    return (
      <div className="bg-gray-100 p-2 rounded-md text-sm mb-4">
        <p className="font-medium">Your user ID:</p>
        <code className="text-xs bg-white p-1 rounded border block overflow-x-auto whitespace-nowrap">{user.id}</code>
        <p className="text-xs mt-1 text-gray-500">Share this ID with others to chat with you directly</p>
      </div>
    )
  }

  return (
    <div className="flex flex-col h-full max-w-4xl mx-auto border rounded-lg overflow-hidden">
      {error && (
        <div className="bg-red-50 border-l-4 border-red-500 p-4 mb-4">
          <div className="flex">
            <div className="flex-shrink-0">
              <svg className="h-5 w-5 text-red-500" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" />
              </svg>
            </div>
            <div className="ml-3">
              <p className="text-sm text-red-700">{error}</p>
            </div>
          </div>
        </div>
      )}
      
      {getUserIdDisplay()}
      
      {currentRoom && (
        <div className="bg-gray-50 p-3 border-b">
          <h2 className="font-semibold">{currentRoom.name}</h2>
          {currentRoom.description && (
            <p className="text-sm text-gray-500">{currentRoom.description}</p>
          )}
        </div>
      )}
      
      <div className="flex-1 p-4 overflow-y-auto">
        {loading ? (
          <div className="flex justify-center items-center h-full">
            <p>Loading messages...</p>
          </div>
        ) : messages.length === 0 ? (
          <div className="flex justify-center items-center h-full">
            <p className="text-gray-500">No messages yet. Start the conversation!</p>
          </div>
        ) : (
          <div className="space-y-4">
            {messages.map((message) => (
              <div
                key={message.id}
                className={`flex ${
                  message.user_id === user.id ? 'justify-end' : 'justify-start'
                }`}
              >
                <div
                  className={`max-w-xs md:max-w-md p-3 rounded-lg ${
                    message.user_id === user.id
                      ? 'bg-blue-500 text-white rounded-tr-none'
                      : 'bg-gray-100 rounded-tl-none'
                  }`}
                >
                  {message.user_id !== user.id && (
                    <p className="text-xs font-semibold mb-1">{message.user_email}</p>
                  )}
                  <p>{message.content}</p>
                  <p className="text-xs mt-1 text-right">
                    {formatDate(message.created_at)}
                  </p>
                </div>
              </div>
            ))}
            <div ref={messagesEndRef} />
          </div>
        )}
      </div>
      
      <form onSubmit={sendMessage} className="border-t p-4 bg-white">
        <div className="flex">
          <input
            type="text"
            value={newMessage}
            onChange={(e) => setNewMessage(e.target.value)}
            placeholder="Type a message..."
            className="flex-1 border rounded-l-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <button
            type="submit"
            disabled={!newMessage.trim() || !currentRoom}
            className="bg-blue-500 text-white px-4 py-2 rounded-r-lg disabled:bg-blue-300 hover:bg-blue-600 transition-colors"
          >
            Send
          </button>
        </div>
      </form>
    </div>
  )
} 