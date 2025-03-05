#!/bin/bash

# Script to update AWS Secrets Manager secret by merging with new JSON attributes
# Usage: ./update_secret.sh <secret-name> <json-file-with-new-attributes>

set -e  # Exit on any error

# Check if required arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <secret-name> <json-file-with-new-attributes>"
    exit 1
fi

SECRET_NAME="$1"
NEW_ATTRIBUTES_FILE="$2"

# Check if the new attributes file exists
if [ ! -f "$NEW_ATTRIBUTES_FILE" ]; then
    echo "Error: JSON file with new attributes '$NEW_ATTRIBUTES_FILE' does not exist."
    exit 1
fi

# Check if file is valid JSON
if ! jq . "$NEW_ATTRIBUTES_FILE" > /dev/null 2>&1; then
    echo "Error: '$NEW_ATTRIBUTES_FILE' is not a valid JSON file."
    exit 1
fi

# Create a temporary file for the merged JSON
TEMP_FILE=$(mktemp)
trap 'rm -f $TEMP_FILE' EXIT  # Clean up temp file on exit

echo "Retrieving current secret value..."
# Get the current secret value
if ! SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query 'SecretString' --output text); then
    echo "Error: Failed to retrieve the secret. Make sure the secret exists and you have appropriate permissions."
    exit 1
fi

echo "Merging JSON attributes..."
# Merge the current secret value with the new attributes
# Using jq to perform a deep merge of the two JSON objects
if ! echo "$SECRET_VALUE" | jq --slurpfile new_attrs "$NEW_ATTRIBUTES_FILE" '. * $new_attrs[0]' > "$TEMP_FILE"; then
    echo "Error: Failed to merge JSON attributes."
    exit 1
fi

echo "Updating secret..."
# Update the secret with the merged JSON
if ! aws secretsmanager update-secret --secret-id "$SECRET_NAME" --secret-string file://"$TEMP_FILE"; then
    echo "Error: Failed to update the secret."
    exit 1
fi

echo "Success! Secret '$SECRET_NAME' has been updated with the merged attributes."