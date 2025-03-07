#!/bin/bash

# Script to update an AWS Secrets Manager secret using a JSON file
# Usage: ./update_secret.sh <secret-name> <json-file-path> [region]

# Check if required arguments are provided
if [ $# -lt 2 ]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 <secret-name> <json-file-path> [region]"
    exit 1
fi

# Assign arguments to variables
SECRET_NAME="$1"
JSON_FILE="$2"
REGION="${3:-us-east-1}"  # Default to us-east-1 if region not provided

# Check if JSON file exists
if [ ! -f "$JSON_FILE" ]; then
    echo "Error: JSON file '$JSON_FILE' not found"
    exit 1
fi

# Validate JSON format
if ! jq empty "$JSON_FILE" 2>/dev/null; then
    echo "Error: Invalid JSON format in '$JSON_FILE'"
    exit 1
fi

# Get the content of the JSON file
SECRET_STRING=$(cat "$JSON_FILE")

# Update the secret
echo "Updating secret '$SECRET_NAME' in region '$REGION'..."
aws secretsmanager update-secret \
    --secret-id "$SECRET_NAME" \
    --secret-string "$SECRET_STRING" \
    --region "$REGION"

# Check if the update was successful
if [ $? -eq 0 ]; then
    echo "Secret '$SECRET_NAME' successfully updated"
else
    echo "Error: Failed to update secret '$SECRET_NAME'"
    exit 1
fi

exit 0

