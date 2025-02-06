#!/bin/bash

# Check if wagmi CLI is installed globally
if ! command -v wagmi &> /dev/null; then
    echo "wagmi CLI not found, installing..."
    bun install --global @wagmi/cli
fi

# Build contracts first
echo "Building contracts..."
forge build

# Create types directory if it doesn't exist
mkdir -p types

# Generate types using wagmi CLI
echo "Generating types..."
wagmi generate

# Create destination directories if they don't exist
mkdir -p ../pvpvai-frontend/lib/types
mkdir -p ../pvpvai-backend/src/types

# Copy generated types to frontend and backend
echo "Copying types to frontend and backend..."
cp types/generated.ts ../pvpvai-frontend/app/lib/types/
cp types/generated.ts ../pvpvai-backend/src/types/

echo "✨ Types generated and copied successfully!" 