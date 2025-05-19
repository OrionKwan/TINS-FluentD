#!/bin/bash

# Add all files
git add .

# Commit
git commit -m "Initial commit"

# Instructions for connecting to GitHub
echo "To push this repository to GitHub:"
echo "1. Create a new repository on GitHub (https://github.com/new)"
echo "2. Run the following commands to connect and push to GitHub:"
echo ""
echo "   git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git"
echo "   git push -u origin main"
echo ""
echo "Replace YOUR_USERNAME and YOUR_REPO_NAME with your GitHub username and repository name." 