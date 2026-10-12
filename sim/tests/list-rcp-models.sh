#!/bin/sh
# Run on the host (needs EPFL network access). Lists model ids offered by RCP.
set -a; . ./.env; set +a
curl -s -H "Authorization: Bearer $RCP_API_KEY" "$RCP_BASE_URL/models" | jq -r '.data[].id'
