#!/usr/bin/env bash

# NPM Publishing Script for Wormhole Solidity SDK
# 
# Usage:
#   ./publish.sh [tag] [dry-run]
#
# Examples:
#   ./publish.sh              # Publish with 'latest' tag
#   ./publish.sh beta         # Publish with 'beta' tag  
#   ./publish.sh latest true  # Dry run with 'latest' tag
#   ./publish.sh beta true    # Dry run with 'beta' tag

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMP_PUBLISH_DIR="${PROJECT_ROOT_DIR}/dist_npm"

NPM_PACKAGE_NAME="$(node -p "require('${SCRIPT_DIR}/package.json').name")"
NPM_PACKAGE_VERSION="$(node -p "require('${SCRIPT_DIR}/package.json').version")"

NPM_TAG="${1:-latest}"
DRY_RUN="${2:-false}"

# read Solidity version from foundry.toml for Hardhat compilation check
SOLC_VERSION=$(grep -oP '(?<=solc_version = ")[^"]*' "${PROJECT_ROOT_DIR}/foundry.toml")

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

get_npm_version() {
  local result=$(npm view "$1" "$2" --json --silent 2>/dev/null || echo "null")
  if echo "${result}" | grep -q '"error":'; then
    echo "${3:-}"
  elif echo "${result}" | grep -q '"'; then
    echo "${result}" | tr -d '"'
  else
    fail "Failed to get version for package '${1}' with tag '${2}' - error: ${result}"
  fi
}

check_version_increment() {
  LATEST_VERSION=$(get_npm_version "${NPM_PACKAGE_NAME}" "version" "0.0.0")
  if [ "${LATEST_VERSION}" = "0.0.0" ]; then
    echo "Package not found on npm registry. Assuming first publish."
  else
    echo "Latest version on npm: ${LATEST_VERSION}"
  fi

  TAG_VERSION=$(get_npm_version "${NPM_PACKAGE_NAME}" "dist-tags.${NPM_TAG}" "")
  echo "Current '${NPM_TAG}' tag points to: ${TAG_VERSION:-none}"

  if [ "${TAG_VERSION}" = "${NPM_PACKAGE_VERSION}" ]; then
    fail "Version '${NPM_PACKAGE_VERSION}' is already published to tag '${NPM_TAG}'."
  fi

  if [ "${LATEST_VERSION}" != "0.0.0" ] &&
     [ "$(printf '%s\n' "${NPM_PACKAGE_VERSION}" "${LATEST_VERSION}" | sort -V | head -n1)" = "${NPM_PACKAGE_VERSION}" ] &&
     [ "${NPM_PACKAGE_VERSION}" != "${LATEST_VERSION}" ]; then
    fail "Version '${NPM_PACKAGE_VERSION}' is older than latest version '${LATEST_VERSION}'."
  fi
}

# --- Main Script ---

echo "Starting NPM publish process..."
echo "Version: ${NPM_PACKAGE_VERSION}"
echo "Tag:     ${NPM_TAG}"
echo "Dry Run: ${DRY_RUN}"

echo "1. Check Version Against NPM Registry"
check_version_increment

echo "2. Git Status Checks"
if [ "${NPM_TAG}" = "latest" ] && [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
  if [ "${DRY_RUN}" = "true" ]; then
    echo "Warning: not on 'main' branch, but continuing because dry-run."
  else
    fail "Publishing to 'latest' tag but not on the 'main' branch."
  fi
fi
if ! git diff-index --quiet HEAD --; then
  if [ "${DRY_RUN}" = "true" ]; then
    echo "Warning: There are uncommitted changes — continuing because dry-run."
  else
    fail "There are uncommitted changes. Please commit or stash them before publishing."
  fi
fi

echo "3. Cleaning up and setting up temporary publish directory"
rm -rf "${TEMP_PUBLISH_DIR}"
mkdir -p "${TEMP_PUBLISH_DIR}"
(
  cd "${TEMP_PUBLISH_DIR}"
  cp -a "${PROJECT_ROOT_DIR}/src" .
  mv "src" "contracts"
  rm -rf "contracts/testing" "contracts/legacy" # remove stuff that depends on forge-std
  cp "${SCRIPT_DIR}/package.json" "${PROJECT_ROOT_DIR}/README.md" "${PROJECT_ROOT_DIR}/LICENSE" .
  # Make sure the temporary package.json marks the project as ESM so Hardhat (which requires ESM) runs
  if [ -f package.json ] && command -v node >/dev/null 2>&1; then
    node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json","utf8")||"{}");p.type="module";fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n");'
  fi
)

echo "4. Transforming Foundry remappings to relative paths for Hardhat..."
node "${SCRIPT_DIR}/clean_remappings.js" "${PROJECT_ROOT_DIR}" "${TEMP_PUBLISH_DIR}/contracts"

echo "5. Hardhat compilation check"
( 
  cd "${TEMP_PUBLISH_DIR}"
  # Write an ESM Hardhat config (Hardhat requires ESM projects when package.json.type = "module")
  echo "export default { solidity: { version: '${SOLC_VERSION}', settings: { viaIR: true, optimizer: { enabled: true } } } };" > hardhat.config.js
  npm install --no-save --silent hardhat
  if ! npx hardhat compile > /dev/null 2>&1; then
    fail "Hardhat compilation failed. Aborting."
  fi
)

echo "6. Cleaning up temporary files before publishing"
( 
  cd "${TEMP_PUBLISH_DIR}"
  rm -rf hardhat.config.cjs hardhat.config.js node_modules cache artifacts
)

echo "7. Publishing version ${NPM_PACKAGE_VERSION} with tag '${NPM_TAG}'"
( 
  cd "${TEMP_PUBLISH_DIR}"
  npm publish --tag "${NPM_TAG}" $([ "${DRY_RUN}" = "true" ] && echo "--dry-run")
)

echo "8. Cleaning up temporary publish directory: ${TEMP_PUBLISH_DIR}"
rm -rf "${TEMP_PUBLISH_DIR}"

echo "Successfully $([ "${DRY_RUN}" = "true" ] && echo "completed dry run for" || echo "published") version ${NPM_PACKAGE_VERSION} with tag '${NPM_TAG}'"
