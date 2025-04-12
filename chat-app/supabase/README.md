# Supabase Database Setup

This directory contains the SQL scripts for the Chat App's database schema.

## Table of Contents

- [Setup Options](#setup-options)
- [Schema Structure](#schema-structure)
- [Troubleshooting](#troubleshooting)
- [Using Reset and Rebuild](#using-reset-and-rebuild)

## Setup Options

You have two options for setting up the database:

### Option 1: Clean Slate (Recommended)

Use the `reset_and_rebuild.sql` script for a fresh, problem-free database:

1. Open the Supabase SQL Editor
2. Copy the contents of `reset_and_rebuild.sql` and run it
3. This will drop all existing tables and recreate them with non-recursive policies

**Important**: This will delete any existing data in the affected tables.

### Option 2: Incremental Migrations

If you prefer an incremental approach, you can use the migration files:

1. Open the Supabase SQL Editor
2. Use `run_migrations.sql` to run migrations in order
3. If you encounter recursion errors, run `migrations/05_fix_recursive_policy.sql`

## Schema Structure

### Core Tables

- **profiles**: User profile information
- **messages**: Public chat messages in rooms
- **rooms**: Chat rooms/channels
- **room_members**: Membership records for rooms

### Direct Messaging Tables

- **direct_conversations**: Private conversations between users
- **direct_participants**: Users in private conversations
- **direct_messages**: Messages in private conversations

### Feature Tables

- **message_reads**: Read receipts for messages
- **typing_indicators**: Shows when users are typing

## Troubleshooting

### Infinite Recursion Error

If you encounter this error:

```
Database error: infinite recursion detected in policy for relation "room_members"
```

Or:

```
Database error: infinite recursion detected in policy for relation "rooms"
```

The recommended solution is to use the `reset_and_rebuild.sql` script to completely rebuild the database with non-recursive policies.

### Table Already Exists

If you get an error like:

```
ERROR: relation "public.messages" already exists
```

You can safely ignore this error, as the migrations use `CREATE TABLE IF NOT EXISTS` statements.

## Using Reset and Rebuild

The database setup can be done in two ways:

### Option 1: Using the reset_and_rebuild_fixed.sql script (Recommended for clean setup)

1. If you're encountering persistent errors or want to start with a fresh database, use:
   
   ```sql
   \i supabase/reset_and_rebuild_fixed.sql
   ```

   This script:
   - Drops all existing tables, policies, triggers, and functions
   - Rebuilds the entire schema with non-recursive policies
   - Sets up all the necessary tables for chat rooms and direct messaging

2. The fixed version uses PL/pgSQL to properly handle all dependencies by:
   - Dropping all policies first (which resolves most dependency issues)
   - Using dynamic SQL to ensure all triggers are dropped
   - Using CASCADE option for table drops to handle any remaining dependencies

### Option 2: Using Incremental Migrations (For existing setups)

If you prefer an incremental approach, you can use the migration files:

1. Open the Supabase SQL Editor
2. Use `run_migrations.sql` to run migrations in order
3. If you encounter recursion errors, run `migrations/05_fix_recursive_policy.sql`

Note that all existing data will be lost, so use this approach carefully in production environments. 

## Advanced Row-Level Security Patterns

### Departmental Access Control

For implementing department-based access control, there are several approaches:

#### 1. Using Session Variables (Most Efficient)

```sql
-- Create a function to get a user's department
CREATE OR REPLACE FUNCTION public.get_user_department()
RETURNS UUID AS $$
DECLARE
  dept_id UUID;
BEGIN
  SELECT department_id INTO dept_id FROM employee 
  WHERE id = (SELECT employee_id FROM account WHERE login = current_user);
  RETURN dept_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Set a session variable at login time
SELECT set_config('app.user_department', public.get_user_department()::text, false);

-- Use in policies
CREATE POLICY department_access ON employees
  USING (department_id::text = current_setting('app.user_department', true));
```

This approach:
- Caches the department ID in a session variable
- Avoids repeated lookups for each row
- Minimizes database overhead

#### 2. Using Direct Function Calls

```sql
CREATE POLICY department_access ON employees
  USING (department_id = public.get_user_department());
```

Simple but calls the function for each row evaluation.

#### 3. Using Views (Not Recommended)

While creating views like `curr_department` works, it's less efficient as the view subquery is executed for every row. 