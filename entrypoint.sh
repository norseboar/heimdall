#!/bin/bash
set -euo pipefail

BIND="$1"
if [[ -z "${SLACK_TOKEN+x}" ]]; then
  # Read SLACK_TOKEN to configure app if not set:
  # /run/secrets for dev mode (docker-compose)
  # aws ssm for prod mode (AWS ECS)
  export SLACK_TOKEN="$(
    cat /run/secrets/slack_token \
    || aws ssm get-parameters --names /heimdall/slack-token --with-decryption --output text | cut -f4
  )"
fi

gunicorn --bind "$BIND" --access-logfile - wsgi