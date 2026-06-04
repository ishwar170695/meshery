#!/bin/bash

echo "=== TOKEN TEST START ==="

echo "Token length:"
echo ${#GITHUB_TOKEN}

echo "Repository:"
echo "$GITHUB_REPOSITORY"

echo "Actor:"
echo "$GITHUB_ACTOR"

env | grep GITHUB_

echo "=== TOKEN TEST END ==="