#!/bin/bash
set -euo pipefail

BIND="$1"
# Read SLACK_TOKEN to configure app
export SLACK_TOKEN="$(aws ssm get-parameters --names /heimdall/slack-token --with-decryption --output text | cut -f4)"

gunicorn --bind "$BIND" --access-logfile - wsgi