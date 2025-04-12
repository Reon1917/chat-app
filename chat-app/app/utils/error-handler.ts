import { PostgrestError } from '@supabase/supabase-js'

interface ErrorWithMessage {
  message: string
}

type KnownError = PostgrestError | ErrorWithMessage | Error | unknown

/**
 * Handles various types of errors and returns a user-friendly error message
 */
export function handleDatabaseError(error: KnownError): string {
  // Handle PostgrestError
  if (typeof error === 'object' && error !== null) {
    // PostgrestError has a message and code property
    if ('code' in error && 'message' in error && typeof error.message === 'string') {
      const pgError = error as PostgrestError
      
      // Handle common Postgres error codes
      switch (pgError.code) {
        case '42P01': // undefined_table
          return 'The database table does not exist. Please run the SQL setup scripts.'
        
        case '23505': // unique_violation
          return 'A record with this information already exists.'
        
        case '23503': // foreign_key_violation
          return 'This operation references a record that does not exist.'
        
        case '42501': // insufficient_privilege
          return 'You do not have permission to perform this operation.'
        
        case '28000': // invalid_authorization_specification
          return 'Authentication failed. Please log in again.'
        
        case '22P02': // invalid_text_representation 
          return 'Invalid UUID or data format.'
          
        case '54001': // statement_too_complex
          if (pgError.message.includes('infinite recursion')) {
            return 'Infinite recursion detected in policy. Run the fix-recursive-policy.sql script.'
          }
          return 'The database query is too complex.'

        default:
          // Return the PostgreSQL error message if available
          return `Database error: ${pgError.message}` + (pgError.details ? ` (${pgError.details})` : '')
      }
    }
    
    // Handle infinite recursion error that might not have standard code
    if ('message' in error && typeof error.message === 'string') {
      if (error.message.includes('infinite recursion')) {
        return 'Infinite recursion detected in policy. Run the fix-recursive-policy.sql script to fix this issue.'
      }
      return error.message
    }
  }
  
  // Handle unknown errors
  return 'An unknown error occurred. Please try again.'
}

/**
 * Determines if an error is related to a missing database table
 */
export function isTableNotFoundError(error: KnownError): boolean {
  if (typeof error === 'object' && error !== null && 'code' in error) {
    return error.code === '42P01'
  }
  
  if (typeof error === 'object' && error !== null && 'message' in error && typeof error.message === 'string') {
    return error.message.includes('relation') && error.message.includes('does not exist')
  }
  
  return false
}

/**
 * Determines if an error is related to infinite recursion in policies
 */
export function isRecursionError(error: KnownError): boolean {
  if (typeof error === 'object' && error !== null && 'message' in error && typeof error.message === 'string') {
    return error.message.includes('infinite recursion')
  }
  
  return false
}

/**
 * Creates a user-friendly error message with troubleshooting steps
 */
export function createErrorWithHelp(error: KnownError): string {
  const baseMessage = handleDatabaseError(error)
  
  if (isTableNotFoundError(error)) {
    return `${baseMessage} Please make sure you've run all SQL setup scripts in this order: 
    1. schema.sql
    2. schema-enhancements-fixed.sql 
    3. schema-direct-messaging.sql`
  }
  
  if (isRecursionError(error)) {
    return `${baseMessage} To fix this problem, run the fix-recursive-policy.sql script.`
  }
  
  return baseMessage
} 