#!/bin/bash
# Script to archive old SQL files after reorganization
# Run this script from the supabase directory

# Create archive directory if it doesn't exist
mkdir -p ./archive

# Move old SQL files to archive
mv schema.sql ./archive/
mv schema-enhancements.sql ./archive/
mv schema-enhancements-fixed.sql ./archive/
mv schema-enhancements-fixed-recursive.sql ./archive/
mv schema-direct-messaging.sql ./archive/
mv fix-recursive-policy.sql ./archive/

echo "Old SQL files have been moved to the archive directory."
echo "The new migration files in the migrations directory should be used instead." 