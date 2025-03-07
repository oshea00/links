#!/bin/bash

# Script to copy the contents of one AWS secret to another
# Usage: ./copy_secret.sh source_secret_name target_secret_name [region]

# Check if required parameters are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 source_secret_name target_secret_name [region]"
    exit 1
fi

SOURCE_SECRET_NAME="$1"
TARGET_SECRET_NAME="$2"
REGION="${3:-us-east-1}"  # Default to us-east-1 if region not specified

echo "Copying secret from '$SOURCE_SECRET_NAME' to '$TARGET_SECRET_NAME' in region '$REGION'..."

# Get the source secret value
SOURCE_SECRET_VALUE=$(aws secretsmanager get-secret-value \
    --secret-id "$SOURCE_SECRET_NAME" \
    --region "$REGION" \
    --query 'SecretString' \
    --output text)

# Check if the source secret was retrieved successfully
if [ $? -ne 0 ]; then
    echo "Error: Failed to retrieve source secret '$SOURCE_SECRET_NAME'"
    exit 1
fi

# Check if the target secret already exists
TARGET_EXISTS=$(aws secretsmanager describe-secret \
    --secret-id "$TARGET_SECRET_NAME" \
    --region "$REGION" 2>/dev/null)

if [ $? -eq 0 ]; then
    # Target secret exists, update it
    echo "Target secret exists. Updating..."
    aws secretsmanager update-secret \
        --secret-id "$TARGET_SECRET_NAME" \
        --secret-string "$SOURCE_SECRET_VALUE" \
        --region "$REGION"
else
    # Target secret doesn't exist, create it
    echo "Target secret doesn't exist. Creating..."
    aws secretsmanager create-secret \
        --name "$TARGET_SECRET_NAME" \
        --secret-string "$SOURCE_SECRET_VALUE" \
        --region "$REGION"
fi

# Check if the operation was successful
if [ $? -eq 0 ]; then
    echo "Secret copied successfully!"
else
    echo "Error: Failed to create/update target secret '$TARGET_SECRET_NAME'"
    exit 1
fi

