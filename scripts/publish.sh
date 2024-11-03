#!/usr/bin/env bash

root_dir=$(dirname $(realpath $(dirname "$0")))
# if not run from the root, we cd into the root
cd $root_dir

if [[ $NO_CHECK == "" ]]; then
  # Check if the current branch is 'main'
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  if [ "$current_branch" != "main" ]; then
      echo "Error: Not on the 'main' branch. Skip with NO_CHECK=1 if you want to publish anyway."
      exit 1
  fi

  # Check for uncommitted changes
  if ! git diff-index --quiet HEAD --; then
      echo "Error: There are uncommitted changes. Skip with NO_CHECK=1 if you want to publish anyway."
      exit 1
  fi
fi

if [[ -d "contracts" ]]; then
  rm -rf contracts
fi

mkdir contracts

cp -r src/* contracts/.
rm -rf contracts/testing
node scripts/clean-remapping.js

if [[ -d "node_modules" ]]; then
  npm install
fi

# Let's verify that hardhat compiles the contracts
npx hardhat compile

# Check the exit status
if [ $? -ne 0 ]; then
  echo "Compilation failed. Exiting."
  exit 1
fi

# Continue with the rest of your script
echo "Compilation succeeded. Proceeding with the publish process."

node scripts/set-package-json.js
cp README.md contracts/README.md

cd contracts

if [[ $version =~ -([a-zA-Z]+) ]]; then
  tag=${BASH_REMATCH[1]}
  echo "Publishing $tag version $version"
  npm publish --tag $tag
else
  echo "Publishing stable version $version"
  npm publish
fi

cd ..
rm -rf contracts
