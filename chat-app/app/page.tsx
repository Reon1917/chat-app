import { redirect } from 'next/navigation'
import { createClient } from './utils/supabase-server'
import ChatApp from './components/ChatApp'

export default async function Home() {
  const supabase = await createClient()
  
  const { data: { user } } = await supabase.auth.getUser()
  
  if (!user) {
    redirect('/login')
  }
  
  return (
    <div className="flex flex-col min-h-screen">
      <header className="bg-white border-b p-4 flex justify-between items-center">
        <h1 className="text-xl font-bold">Real-time Chat App</h1>
        <div className="flex items-center gap-4">
          <span className="text-sm">{user.email}</span>
          <form action="/auth/signout" method="post">
            <button 
              type="submit" 
              className="px-3 py-1 text-sm bg-gray-100 hover:bg-gray-200 rounded-md"
            >
              Sign out
            </button>
          </form>
        </div>
      </header>
      
      <main className="flex-1 p-4 md:p-6">
        <ChatApp user={user} />
      </main>
      
      <footer className="border-t py-3 text-center text-sm text-gray-500">
        Real-time Chat App with Next.js and Supabase
      </footer>
    </div>
  )
}
