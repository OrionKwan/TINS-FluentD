#!/bin/bash
# Script to check gem availability using RubyGems API

# Function to query RubyGems API for gem details
check_gem() {
  local gem_name=$1
  echo "Checking availability of gem: $gem_name"
  curl -s "https://rubygems.org/api/v1/gems/$gem_name.json" | jq -r '. | "Name: \(.name)\nLatest Version: \(.version)\nDescription: \(.info)\nDownloads: \(.downloads)\nHomepage: \(.homepage_uri)\n"'
  echo "---"
  echo "Version History:"
  curl -s "https://rubygems.org/api/v1/versions/$gem_name.json" | jq -r '.[] | "Version: \(.number), Created: \(.created_at)"' | head -5
  echo "---"
  echo "Dependencies:"
  curl -s "https://rubygems.org/api/v1/gems/$gem_name.json" | jq -r '.dependencies.runtime[] | "\(.name) (\(.requirements))"'
  echo "============================================================="
}

# List of UDP-related gems to check
gems_to_check=(
  "fluent-plugin-udp"
  "fluent-plugin-out-udp"
  "fluent-plugin-udp-native"
  "fluent-plugin-socket"
  "fluent-plugin-remote_syslog"
  "fluent-plugin-netflow"
)

# Check each gem
for gem in "${gems_to_check[@]}"; do
  check_gem "$gem"
done
