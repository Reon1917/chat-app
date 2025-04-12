# Real-time Chat App with Next.js and Supabase

A real-time chat application built with Next.js and Supabase for authentication and real-time messaging.

## Features

- User authentication (sign up, sign in, sign out)
- Real-time messaging
- Message history
- User profiles

## Tech Stack

- **Next.js 15** - React framework
- **Supabase** - Backend as a Service
  - Authentication
  - PostgreSQL Database
  - Real-time subscriptions
- **Tailwind CSS** - Styling

## Setup Instructions

### 1. Create a Supabase project

1. Sign up at [Supabase](https://supabase.com) and create a new project
2. Get your project URL and anon key from the API settings
3. Run the SQL from `supabase/schema.sql` in the SQL editor to set up the database schema

### 2. Configure environment variables

Create a `.env.local` file in the root directory with the following variables:

```
NEXT_PUBLIC_SUPABASE_URL=your-supabase-url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-supabase-anon-key
```

### 3. Install dependencies

```bash
npm install
```

### 4. Run the development server

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

## Authentication Flow

1. Users can sign up with email and password
2. Email verification is enabled by default
3. After verification, users can sign in
4. Authentication state is maintained using cookies and refreshed in middleware

## Database Structure

- **messages** - Stores all chat messages
- **profiles** - Stores user profile information
  
## Deployment

Deploy on Vercel for the best experience with Next.js:

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/git/external?repository-url=https://github.com/yourusername/real-time-chat-app)
