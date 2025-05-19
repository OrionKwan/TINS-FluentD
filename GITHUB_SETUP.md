# GitHub Setup and Maintenance Guide

## What We've Done So Far

### 1. Git Repository Initialization
- Initialized a local Git repository in the project directory
- Created a `.gitignore` file to exclude unnecessary files
- Made an initial commit of the codebase

### 2. GitHub Connection
- Connected the local repository to the GitHub remote at https://github.com/OrionKwan/TINS-FluentD
- Merged the remote README with the local version
- Successfully pushed all local files to the GitHub repository

### 3. Conflict Resolution
- Resolved merge conflicts between local and remote repositories
- Successfully combined the existing GitHub README with the more detailed local version
- Committed the merged changes

## Version Management Guide

### Semantic Versioning
For this project, follow semantic versioning (SemVer) with the format: `MAJOR.MINOR.PATCH`

- **MAJOR**: Increment when making incompatible API changes
- **MINOR**: Increment when adding functionality in a backwards-compatible manner
- **PATCH**: Increment when making backwards-compatible bug fixes

### Creating Version Tags
```bash
# Create a tag for a specific version
git tag -a v1.0.0 -m "Version 1.0.0 - Initial stable release"

# Push tags to GitHub
git push origin --tags
```

### Creating Releases
1. Go to the GitHub repository's "Releases" section
2. Click "Create a new release"
3. Select the tag version
4. Add a title and description
5. Optionally attach compiled binaries or packages
6. Publish the release

## GitHub Maintenance Guide

### Regular Workflow
```bash
# Pull latest changes before starting work
git pull origin main

# Create a feature branch (recommended for new features)
git checkout -b feature/your-feature-name

# Make changes and commit them
git add .
git commit -m "Description of changes"

# Push changes to GitHub
git push origin feature/your-feature-name  # If on feature branch
# OR
git push origin main  # If working directly on main branch
```

### Branch Management
- Use `main` for stable, working code
- Create feature branches for new development
- Use pull requests for code review before merging features

### Issue Tracking
- Use GitHub Issues to track bugs and feature requests
- Link commits to issues by mentioning the issue number in commit messages
  - Example: `git commit -m "Fix SNMP authentication issue #42"`

### GitHub Actions (Optional Future Setup)
- Consider setting up GitHub Actions for automated testing
- Create a `.github/workflows` directory with workflow definition files
- Example workflow could run tests on each push

### Documentation Updates
- Keep README.md updated with new features and changes
- Update any usage instructions when the API or workflow changes
- Consider using GitHub Wiki for more detailed documentation

## Troubleshooting

### Authentication Issues
- Use a Personal Access Token (PAT) for HTTPS authentication
- Or set up SSH keys for easier authentication

### Merge Conflicts
```bash
# When conflicts occur
git status  # To see which files have conflicts
# Edit the files to resolve conflicts
git add .  # Add resolved files
git commit  # Complete the merge
```

### Undoing Mistakes
```bash
# Undo the last commit (keeping changes)
git reset --soft HEAD~1

# Discard all local changes
git reset --hard origin/main
``` 