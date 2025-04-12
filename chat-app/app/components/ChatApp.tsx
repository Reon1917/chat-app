'use client'

import { useState } from 'react'
import { User } from '@supabase/supabase-js'
import ChatInterface from './ChatInterface'
import DirectMessage from './DirectMessage'

interface ChatAppProps {
  user: User
}

export default function ChatApp({ user }: ChatAppProps) {
  const [activeTab, setActiveTab] = useState<'rooms' | 'direct'>('rooms')
  
  return (
    <div className="w-full">
      <div className="border-b mb-4 flex">
        <button
          className={`py-2 px-4 font-medium ${
            activeTab === 'rooms' 
              ? 'border-b-2 border-blue-500 text-blue-600' 
              : 'text-gray-500 hover:text-gray-700'
          }`}
          onClick={() => setActiveTab('rooms')}
        >
          Chat Rooms
        </button>
        <button
          className={`py-2 px-4 font-medium ${
            activeTab === 'direct' 
              ? 'border-b-2 border-blue-500 text-blue-600' 
              : 'text-gray-500 hover:text-gray-700'
          }`}
          onClick={() => setActiveTab('direct')}
        >
          Direct Messages
        </button>
      </div>
      
      <div className="mt-0">
        {activeTab === 'rooms' ? (
          <ChatInterface user={user} />
        ) : (
          <DirectMessage user={user} />
        )}
      </div>
    </div>
  )
} 