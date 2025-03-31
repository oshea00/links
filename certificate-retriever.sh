#!/bin/bash
set -e

# Azure Entra ID Certificate Retriever
# This script retrieves a certificate from AWS Secrets Manager and uses it to get an Azure Entra ID token

# Default values
REGION="us-east-1"
WORKING_DIR=$(mktemp -d)

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --secret-name)
      SECRET_NAME="$2"
      shift 2
      ;;
    --tenant-id)
      TENANT_ID="$2"
      shift 2
      ;;
    --client-id)
      CLIENT_ID="$2"
      shift 2
      ;;
    --scope)
      SCOPE="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check required parameters
if [ -z "$SECRET_NAME" ] || [ -z "$TENANT_ID" ] || [ -z "$CLIENT_ID" ] || [ -z "$SCOPE" ]; then
  echo "Usage: $0 --secret-name <secret-name> --tenant-id <tenant-id> --client-id <client-id> --scope <scope> [--region <aws-region>]"
  exit 1
fi

# Get certificate info from AWS Secrets Manager
echo "Retrieving certificate from AWS Secrets Manager '$SECRET_NAME'..."
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "$REGION" --query SecretString --output text)

# Extract values from JSON
PFX_BASE64=$(echo "$SECRET_JSON" | jq -r '.pfx_base64')
PASSWORD=$(echo "$SECRET_JSON" | jq -r '.password')
THUMBPRINT=$(echo "$SECRET_JSON" | jq -r '.thumbprint')

# File paths
PFX_FILE="$WORKING_DIR/certificate.pfx"
PRIVATE_KEY="$WORKING_DIR/private.key"
CERT_FILE="$WORKING_DIR/cert.crt"
JWT_HEADER_FILE="$WORKING_DIR/jwt_header.json"
JWT_PAYLOAD_FILE="$WORKING_DIR/jwt_payload.json"
SIGNATURE_FILE="$WORKING_DIR/signature.bin"

# Decode the PFX file
echo "$PFX_BASE64" | base64 -d > "$PFX_FILE"

# Extract private key and certificate
openssl pkcs12 -in "$PFX_FILE" -nocerts -nodes -out "$PRIVATE_KEY" -passin "pass:$PASSWORD"
openssl pkcs12 -in "$PFX_FILE" -clcerts -nokeys -out "$CERT_FILE" -passin "pass:$PASSWORD"

# Create JWT header
cat > "$JWT_HEADER_FILE" << EOF
{
  "alg": "RS256",
  "typ": "JWT",
  "x5t": "$(echo -n "$THUMBPRINT" | xxd -r -p | base64 | tr -d '\n=' | tr '/+' '_-')"
}
EOF

# Current time and expiry time (5 minutes)
NOW=$(date +%s)
EXP=$((NOW + 300))

# Create JWT payload
cat > "$JWT_PAYLOAD_FILE" << EOF
{
  "aud": "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token",
  "exp": $EXP,
  "iss": "$CLIENT_ID",
  "jti": "$(openssl rand -hex 16)",
  "nbf": $NOW,
  "sub": "$CLIENT_ID",
  "iat": $NOW
}
EOF

# Base64url encode header and payload
JWT_HEADER_BASE64=$(cat "$JWT_HEADER_FILE" | jq -c | base64 | tr -d '\n=' | tr '/+' '_-')
JWT_PAYLOAD_BASE64=$(cat "$JWT_PAYLOAD_FILE" | jq -c | base64 | tr -d '\n=' | tr '/+' '_-')

# Create signing input
JWT_SIGNING_INPUT="$JWT_HEADER_BASE64.$JWT_PAYLOAD_BASE64"

# Create signature
echo -n "$JWT_SIGNING_INPUT" | openssl dgst -sha256 -sign "$PRIVATE_KEY" -out "$SIGNATURE_FILE"
JWT_SIGNATURE_BASE64=$(base64 -w 0 < "$SIGNATURE_FILE" | tr -d '=' | tr '/+' '_-')

# Create complete JWT
CLIENT_ASSERTION="$JWT_HEADER_BASE64.$JWT_PAYLOAD_BASE64.$JWT_SIGNATURE_BASE64"

echo "Creating client assertion JWT..."
echo "Requesting access token from Azure Entra ID..."

# Request token from Azure
TOKEN_RESPONSE=$(curl -s -X POST "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$CLIENT_ID" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$CLIENT_ASSERTION" \
  -d "scope=$SCOPE" \
  -d "grant_type=client_credentials")

# Extract values from the token response
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [ -n "$ACCESS_TOKEN" ]; then
  TOKEN_TYPE=$(echo "$TOKEN_RESPONSE" | jq -r '.token_type')
  EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')
  
  echo ""
  echo "Access token obtained successfully!"
  echo "Token type: $TOKEN_TYPE"
  echo "Expires in: $EXPIRES_IN seconds"
  echo "Access token: ${ACCESS_TOKEN:0:50}..."
else
  echo "Failed to obtain access token:"
  echo "$TOKEN_RESPONSE" | jq .
fi

# Clean up temporary files
rm -rf "$WORKING_DIR"
