#!/bin/bash

echo "=== TOKEN TEST START ==="

curl -s \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/$GITHUB_REPOSITORY

echo
echo "=== TOKEN TEST END ==="