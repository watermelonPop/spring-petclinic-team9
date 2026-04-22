#!/usr/bin/env bash
set -euo pipefail

mkdir -p /burp/reports

BURP_ARGS=()
if [[ -n "${BURP_PROJECT_FILE:-}" ]]; then
  mkdir -p "$(dirname "${BURP_PROJECT_FILE}")"
  BURP_ARGS+=("--project-file=${BURP_PROJECT_FILE}")
fi

java -jar /opt/burp/burpsuite_community.jar "${BURP_ARGS[@]}" &
wait -n
