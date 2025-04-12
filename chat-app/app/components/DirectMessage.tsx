'use client'

import { useState, useEffect, useRef } from 'react'
import { User } from '@supabase/supabase-js'
import { createClient } from '../utils/supabase-browser'
import { z } from 'zod'
import { createErrorWithHelp } from '../utils/error-handler'

// Zod schemas for validation
const DirectMessageSchema = z.object({
  id: z.string().uuid(),
  content: z.string(),
  created_at: z.string(),
  conversation_id: z.string().uuid(),
  sender_id: z.string().uuid()
})

const ConversationSchema = z.object({
  id: z.string().uuid(),
  created_at: z.string(),
  updated_at: z.string()
})

const ProfileSchema = z.object({
  id: z.string().uuid().optional(),
  username: z.string().optional().nullable()
})

interface DirectMessage {
  id: string
  content: string
  created_at: string
  conversation_id: string
  sender_id: string
}

interface Conversation {
  id: string
  created_at: string
  updated_at: string
  otherUser?: {
    id: string
    email: string
  }
}

interface DirectMessageProps {
  user: User
}

export default function DirectMessage({ user }: DirectMessageProps) {
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [selectedConversation, setSelectedConversation] = useState<Conversation | null>(null)
  const [messages, setMessages] = useState<DirectMessage[]>([])
  const [newMessage, setNewMessage] = useState('')
  const [newContactId, setNewContactId] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [showNewConversationDialog, setShowNewConversationDialog] = useState(false)
  const [showUserId, setShowUserId] = useState(false)
  const [copySuccess, setCopySuccess] = useState('')
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const supabase = createClient()
  
  // Fetch conversations
  useEffect(() => {
    const fetchConversations = async () => {
      try {
        setError(null)
        
        // Get all conversations the user is part of
        const { data: participations, error: partError } = await supabase
          .from('direct_participants')
          .select('conversation_id')
          .eq('user_id', user.id)
        
        if (partError) {
          console.error('Error fetching participations:', partError)
          setError(createErrorWithHelp(partError))
          return
        }
        
        if (!participations?.length) {
          setConversations([])
          setLoading(false)
          return
        }
        
        const conversationIds = participations.map(p => p.conversation_id)
        
        // Get all conversation details
        const { data: convoData, error: convoError } = await supabase
          .from('direct_conversations')
          .select('*')
          .in('id', conversationIds)
          .order('updated_at', { ascending: false })
        
        if (convoError) {
          console.error('Error fetching conversations:', convoError)
          setError(createErrorWithHelp(convoError))
          return
        }
        
        if (!convoData || convoData.length === 0) {
          setConversations([])
          setLoading(false)
          return
        }
        
        // Validate conversation data
        const validatedConvoData = convoData.map(convo => {
          try {
            return ConversationSchema.parse(convo)
          } catch (parseError) {
            console.warn('Conversation validation error:', parseError)
            // Provide defaults
            return {
              id: convo.id || '',
              created_at: convo.created_at || new Date().toISOString(),
              updated_at: convo.updated_at || new Date().toISOString()
            }
          }
        })
        
        // For each conversation, get the other participant
        const conversationsWithUsers = await Promise.all(
          validatedConvoData.map(async (convo) => {
            try {
              const { data: participants, error: partError } = await supabase
                .from('direct_participants')
                .select('user_id')
                .eq('conversation_id', convo.id)
                .neq('user_id', user.id)
              
              if (partError) {
                console.warn('Error fetching participants:', partError)
                return convo
              }
              
              if (!participants?.length) {
                return convo
              }
              
              const otherUserId = participants[0].user_id
              
              // Get user details - using profiles instead of admin API
              const { data: profileData, error: profileError } = await supabase
                .from('profiles')
                .select('username')
                .eq('id', otherUserId)
                .single()
              
              if (profileError) {
                console.warn('Error fetching profile:', profileError)
              }
              
              let email = 'Unknown User'
              
              // Validate profile data
              if (profileData) {
                try {
                  const validatedProfile = ProfileSchema.parse(profileData)
                  if (validatedProfile.username) {
                    email = validatedProfile.username
                  }
                } catch (parseError) {
                  console.warn('Profile validation error:', parseError)
                }
              }
              
              return {
                ...convo,
                otherUser: {
                  id: otherUserId,
                  email: email
                }
              }
            } catch (error) {
              console.error('Error processing conversation:', error)
              return convo
            }
          })
        )
        
        setConversations(conversationsWithUsers)
        
        // If there are conversations and none is selected, select the first one
        if (conversationsWithUsers.length > 0 && !selectedConversation) {
          setSelectedConversation(conversationsWithUsers[0])
        }
      } catch (error: any) {
        console.error('Error in fetchConversations:', error)
        setError(createErrorWithHelp(error))
      } finally {
        setLoading(false)
      }
    }
    
    fetchConversations()
  }, [user.id])
  
  // Fetch messages when conversation changes
  useEffect(() => {
    if (selectedConversation) {
      fetchMessages(selectedConversation.id)
      subscribeToMessages(selectedConversation.id)
    }
  }, [selectedConversation])
  
  // Scroll to bottom when messages change
  useEffect(() => {
    scrollToBottom()
  }, [messages])
  
  const fetchMessages = async (conversationId: string) => {
    try {
      setLoading(true)
      setError(null)
      
      const { data, error } = await supabase
        .from('direct_messages')
        .select('*')
        .eq('conversation_id', conversationId)
        .order('created_at', { ascending: true })
      
      if (error) {
        throw error
      }
      
      setMessages(data || [])
    } catch (error: any) {
      console.error('Error fetching messages:', error)
      setError(createErrorWithHelp(error))
    } finally {
      setLoading(false)
    }
  }
  
  const subscribeToMessages = (conversationId: string) => {
    const channel = supabase
      .channel(`direct_messages:${conversationId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'direct_messages',
          filter: `conversation_id=eq.${conversationId}`
        },
        (payload) => {
          const newMessage = payload.new as DirectMessage
          setMessages((prev) => [...prev, newMessage])
        }
      )
      .subscribe()
    
    return () => {
      supabase.removeChannel(channel)
    }
  }
  
  const sendMessage = async (e: React.FormEvent) => {
    e.preventDefault()
    
    if (!newMessage.trim() || !selectedConversation) return
    
    try {
      setError(null)
      
      const { error } = await supabase
        .from('direct_messages')
        .insert({
          conversation_id: selectedConversation.id,
          sender_id: user.id,
          content: newMessage.trim()
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
  
  const startConversation = async () => {
    if (!newContactId.trim()) return
    
    try {
      setError(null)
      
      // Validate the user ID format
      try {
        z.string().uuid().parse(newContactId.trim())
      } catch (validationError) {
        setError('Invalid user ID format. Please enter a valid UUID.')
        return
      }
      
      // Check if the user exists
      const { data: userExists, error: userCheckError } = await supabase
        .from('profiles')
        .select('id')
        .eq('id', newContactId.trim())
        .single()
      
      if (userCheckError || !userExists) {
        setError('User not found. Please check the ID and try again.')
        return
      }
      
      // Call the Supabase function to find or create conversation
      const { data, error } = await supabase
        .rpc('find_or_create_conversation', {
          user1_id: user.id,
          user2_id: newContactId.trim()
        })
      
      if (error) {
        throw error
      }
      
      if (!data) {
        setError('Failed to create conversation - no conversation ID returned')
        return
      }
      
      // Refresh conversations
      const { data: convoData, error: convoError } = await supabase
        .from('direct_conversations')
        .select('*')
        .eq('id', data)
        .single()
      
      if (convoError) {
        throw convoError
      }
      
      // Validate conversation data
      let validatedConvo
      try {
        validatedConvo = ConversationSchema.parse(convoData)
      } catch (parseError) {
        console.warn('Conversation validation error:', parseError)
        validatedConvo = {
          id: convoData.id || '',
          created_at: convoData.created_at || new Date().toISOString(),
          updated_at: convoData.updated_at || new Date().toISOString()
        }
      }
      
      // Get the other user's profile
      const { data: profileData, error: profileError } = await supabase
        .from('profiles')
        .select('username')
        .eq('id', newContactId.trim())
        .single()
      
      let email = 'Unknown User'
      
      // Validate profile data
      if (profileData) {
        try {
          const validatedProfile = ProfileSchema.parse(profileData)
          if (validatedProfile.username) {
            email = validatedProfile.username
          }
        } catch (parseError) {
          console.warn('Profile validation error:', parseError)
        }
      }
      
      const newConversation = {
        ...validatedConvo,
        otherUser: {
          id: newContactId.trim(),
          email: email
        }
      }
      
      // Update the conversations list
      setConversations(prev => [newConversation, ...prev])
      setSelectedConversation(newConversation)
      setNewContactId('')
      setShowNewConversationDialog(false)
    } catch (error: any) {
      console.error('Error starting conversation:', error)
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
  
  const getInitials = (email: string) => {
    return email.substring(0, 2).toUpperCase()
  }
  
  const copyToClipboard = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text)
      setCopySuccess('Copied!')
      setTimeout(() => setCopySuccess(''), 2000)
    } catch (err) {
      setCopySuccess('Failed to copy')
      setTimeout(() => setCopySuccess(''), 2000)
    }
  }
  
  return (
    <div className="flex flex-col h-[80vh] border rounded-lg">
      <div className="p-3 border-b flex justify-between items-center">
        <h2 className="text-xl font-bold">Direct Messages</h2>
        <div className="flex items-center gap-2">
          <div className="text-sm text-gray-500">
            Your ID:
            <span className="relative ml-2 bg-gray-100 px-2 py-1 rounded">
              {showUserId ? user.id : '••••••••••••••'}
              <button 
                onClick={() => setShowUserId(!showUserId)} 
                className="ml-1 text-blue-500 hover:text-blue-700"
                title={showUserId ? "Hide ID" : "Show ID"}
              >
                {showUserId ? '👁️' : '👁️‍🗨️'}
              </button>
              <button 
                onClick={() => copyToClipboard(user.id)} 
                className="ml-1 text-blue-500 hover:text-blue-700"
                title="Copy ID"
              >
                📋
              </button>
              {copySuccess && <span className="absolute text-xs text-green-500 top-full left-0 mt-1">{copySuccess}</span>}
            </span>
          </div>
        </div>
      </div>
      
      <div className="flex-1 flex gap-2 p-2 overflow-hidden">
        {/* Conversations sidebar */}
        <div className="w-1/3 border rounded-md overflow-y-auto">
          <div className="p-2 sticky top-0 bg-white border-b">
            <button 
              className="w-full bg-blue-500 hover:bg-blue-600 text-white font-medium py-2 px-4 rounded"
              onClick={() => setShowNewConversationDialog(true)}
            >
              New Conversation
            </button>
          </div>
          
          {conversations.length === 0 ? (
            <div className="p-4 text-center text-gray-500">
              No conversations yet
            </div>
          ) : (
            <div className="divide-y">
              {conversations.map((convo) => (
                <div
                  key={convo.id}
                  className={`p-3 flex items-center gap-3 cursor-pointer hover:bg-gray-50 ${
                    selectedConversation?.id === convo.id ? 'bg-gray-100' : ''
                  }`}
                  onClick={() => setSelectedConversation(convo)}
                >
                  <div className="w-10 h-10 rounded-full bg-gray-300 flex items-center justify-center text-gray-700 font-medium">
                    {convo.otherUser ? getInitials(convo.otherUser.email) : '??'}
                  </div>
                  <div className="overflow-hidden">
                    <p className="font-medium truncate">
                      {convo.otherUser?.email || 'Unknown User'}
                    </p>
                    <p className="text-xs text-gray-500">
                      {new Date(convo.updated_at).toLocaleDateString()}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
        
        {/* Messages area */}
        <div className="w-2/3 border rounded-md flex flex-col overflow-hidden">
          {!selectedConversation ? (
            <div className="flex-1 flex items-center justify-center text-gray-500">
              Select a conversation or start a new one
            </div>
          ) : (
            <>
              <div className="p-3 border-b flex items-center gap-2">
                <div className="w-8 h-8 rounded-full bg-gray-300 flex items-center justify-center text-gray-700 font-medium">
                  {selectedConversation.otherUser 
                    ? getInitials(selectedConversation.otherUser.email) 
                    : '??'}
                </div>
                <div>
                  <p className="font-medium">
                    {selectedConversation.otherUser?.email || 'Unknown User'}
                  </p>
                </div>
              </div>
              
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
                          message.sender_id === user.id ? 'justify-end' : 'justify-start'
                        }`}
                      >
                        <div
                          className={`max-w-xs md:max-w-md p-3 rounded-lg ${
                            message.sender_id === user.id
                              ? 'bg-blue-500 text-white rounded-tr-none'
                              : 'bg-gray-100 rounded-tl-none'
                          }`}
                        >
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
              
              <form onSubmit={sendMessage} className="border-t p-3">
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={newMessage}
                    onChange={(e) => setNewMessage(e.target.value)}
                    placeholder="Type a message..."
                    className="flex-1 border rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <button 
                    type="submit" 
                    disabled={!newMessage.trim() || !selectedConversation}
                    className="bg-blue-500 hover:bg-blue-600 disabled:bg-blue-300 text-white font-medium py-2 px-4 rounded"
                  >
                    Send
                  </button>
                </div>
              </form>
            </>
          )}
        </div>
      </div>
      
      {error && (
        <div className="px-6 py-2 text-sm text-red-600 bg-red-50 border-t">
          {error}
        </div>
      )}
      
      {/* New Conversation Dialog */}
      {showNewConversationDialog && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50">
          <div className="bg-white rounded-lg shadow-lg max-w-md w-full p-6">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-lg font-semibold">Start a conversation</h3>
              <button 
                onClick={() => setShowNewConversationDialog(false)}
                className="text-gray-500 hover:text-gray-700"
              >
                ✕
              </button>
            </div>
            <div className="mb-4">
              <label className="block text-sm font-medium mb-2">
                Enter User ID
              </label>
              <div className="relative">
                <input
                  type="text"
                  placeholder="Paste User ID here"
                  value={newContactId}
                  onChange={(e) => setNewContactId(e.target.value)}
                  className="w-full border rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
                {newContactId && (
                  <button
                    className="absolute right-2 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600"
                    onClick={() => setNewContactId('')}
                    title="Clear"
                  >
                    ✕
                  </button>
                )}
              </div>
              <div className="flex justify-between items-center">
                <p className="text-xs text-gray-500 mt-1">
                  Ask the other person to share their User ID
                </p>
                <div className="text-xs text-blue-500 mt-1 cursor-pointer" onClick={() => copyToClipboard(user.id)}>
                  Share your ID {copySuccess && <span className="text-green-500">({copySuccess})</span>}
                </div>
              </div>
            </div>
            <div className="flex justify-end space-x-2">
              <button
                onClick={() => setShowNewConversationDialog(false)}
                className="px-4 py-2 border rounded text-gray-700 hover:bg-gray-50"
              >
                Cancel
              </button>
              <button
                onClick={startConversation}
                disabled={!newContactId.trim()}
                className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:bg-blue-300"
              >
                Start Conversation
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
} 