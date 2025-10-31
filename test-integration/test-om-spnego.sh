#!/usr/bin/env bash
# Test om CLI with SPNEGO proxy authentication
# This tests the CLI flag parsing and environment setup

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

log_step() { echo -e "${BLUE}${BOLD}$1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] ✓ $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] ✗ $1${NC}"; }
log_info() { echo -e "${BOLD}[INFO] $1${NC}"; }

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                                                                    ║${NC}"
echo -e "${BOLD}║              OM CLI SPNEGO AUTHENTICATION TEST                     ║${NC}"
echo -e "${BOLD}║                                                                    ║${NC}"
echo -e "${BOLD}║  Tests flag parsing with SPNEGO proxy authentication flags         ║${NC}"
echo -e "${BOLD}║                                                                    ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
log_step "▶ Step 1: Checking Prerequisites"
echo ""

if ! docker ps --format "{{.Names}}" | grep -q "test-kerberos-kdc"; then
	log_error "Kerberos KDC not running. Start with: cd $SCRIPT_DIR && docker-compose up -d"
	exit 1
fi
log_success "Kerberos KDC running (localhost:88)"

if ! docker ps --format "{{.Names}}" | grep -q "test-apache-proxy"; then
	log_error "Apache proxy not running. Start with: cd $SCRIPT_DIR && docker-compose up -d"
	exit 1
fi
log_success "Apache proxy running (localhost:3128)"

echo ""
log_step "▶ Step 2: Building om CLI"
echo ""

cd "$CLI_DIR"

# Remove old binary to ensure we get a fresh build
rm -f om-TEST

# Touch source files to force Go to recompile (Go caches based on mtime)
touch commands/*.go network/*.go 2>/dev/null || true

log_info "Building fresh binary with unique name..."
if ! go build -o om-TEST .; then
	log_error "Failed to build om-TEST"
	exit 1
fi

# Verify the binary was just created
BUILD_TIME=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" om-TEST 2>/dev/null || stat -c "%y" om-TEST 2>/dev/null | cut -d. -f1)
log_success "CLI built: $CLI_DIR/om-TEST"
log_info "Build timestamp: $BUILD_TIME"
log_info "Binary hash: $(md5 -q om-TEST 2>/dev/null || md5sum om-TEST | cut -d' ' -f1)"

echo ""
log_step "▶ Step 3: Testing om CLI with SPNEGO Flags"
echo ""

# Export proxy and Kerberos configuration for the CLI
export HTTP_PROXY="http://localhost:3128"
export HTTPS_PROXY="http://localhost:3128"
export KRB5_CONFIG="$SCRIPT_DIR/krb5-host.conf"

# SPNEGO credentials to pass via CLI flags (which don't exist yet)
PROXY_USERNAME="testuser"
PROXY_PASSWORD="testpass123"
PROXY_DOMAIN="TEST.LOCAL"

# Dummy Ops Manager credentials for clean testing
TARGET_URL="https://example.com"
OM_USERNAME="admin"
OM_PASSWORD="admin"

log_info "SPNEGO Configuration:"
echo "  Username: $PROXY_USERNAME (will be passed via --proxy-username flag)"
echo "  Domain:   $PROXY_DOMAIN (will be passed via --proxy-domain flag)"
echo "  HTTP Proxy: $HTTP_PROXY (from environment)"
echo "  HTTPS Proxy: $HTTPS_PROXY (from environment)"
echo "  KRB5_CONFIG: $KRB5_CONFIG (from environment)"
echo ""

log_info "Testing om products with SPNEGO proxy authentication flags..."
log_info "Expected: 'unknown flag' errors since SPNEGO support not yet implemented"
echo ""

log_info "Command to execute:"
echo "  $CLI_DIR/om-TEST \\"
echo "    --target \"$TARGET_URL\" \\"
echo "    --username \"$OM_USERNAME\" \\"
echo "    --password \"***\" \\"
echo "    --skip-ssl-validation \\"
echo "    --proxy-username \"$PROXY_USERNAME\" \\"
echo "    --proxy-password \"***\" \\"
echo "    --proxy-domain \"$PROXY_DOMAIN\" \\"
echo "    products"
echo ""

# Run the CLI - we EXPECT this to fail with "unknown flag"
# Note: Global flags must come BEFORE the command in om
set +e
"$CLI_DIR/om-TEST" \
	--target "$TARGET_URL" \
	--username "$OM_USERNAME" \
	--password "$OM_PASSWORD" \
	--skip-ssl-validation \
	--proxy-username "$PROXY_USERNAME" \
	--proxy-password "$PROXY_PASSWORD" \
	--proxy-domain "$PROXY_DOMAIN" \
	products 2>&1 | tee /tmp/om-spnego-output.log
EXIT_CODE=${PIPESTATUS[0]}
set -e

echo ""
log_step "▶ Step 4: Results"
echo ""

echo "Exit Code: $EXIT_CODE"
echo ""

# Check the output for expected error message
if grep -qi "unknown.*flag.*proxy-username" /tmp/om-spnego-output.log 2>/dev/null; then
	log_success "═══════════════════════════════════════════════════════════════"
	log_success "🎉 SUCCESS! Test environment is working correctly! 🎉"
	log_success "═══════════════════════════════════════════════════════════════"
	echo ""
	log_info "What was verified:"
	echo "  ✓ Docker environment running (KDC + Apache proxy)"
	echo "  ✓ om CLI builds successfully"
	echo "  ✓ Test script can execute om with all required flags"
	echo "  ✓ SPNEGO flags properly rejected (as expected - not yet implemented)"
	echo ""
	log_info "Next steps:"
	echo "  1. Implement SPNEGO support in om CLI"
	echo "  2. Add --proxy-username, --proxy-password, --proxy-domain flags"
	echo "  3. Re-run this test to verify implementation"
	echo ""
	exit 0
elif grep -qi "unknown.*flag.*proxy-password" /tmp/om-spnego-output.log 2>/dev/null; then
	log_success "═══════════════════════════════════════════════════════════════"
	log_success "🎉 SUCCESS! Test environment is working correctly! 🎉"
	log_success "═══════════════════════════════════════════════════════════════"
	echo ""
	log_info "What was verified:"
	echo "  ✓ Docker environment running (KDC + Apache proxy)"
	echo "  ✓ om CLI builds successfully"
	echo "  ✓ Test script can execute om with all required flags"
	echo "  ✓ SPNEGO flags properly rejected (as expected - not yet implemented)"
	echo ""
	log_info "Next steps:"
	echo "  1. Implement SPNEGO support in om CLI"
	echo "  2. Add --proxy-username, --proxy-password, --proxy-domain flags"
	echo "  3. Re-run this test to verify implementation"
	echo ""
	exit 0
elif grep -qi "unknown.*flag.*proxy-domain" /tmp/om-spnego-output.log 2>/dev/null; then
	log_success "═══════════════════════════════════════════════════════════════"
	log_success "🎉 SUCCESS! Test environment is working correctly! 🎉"
	log_success "═══════════════════════════════════════════════════════════════"
	echo ""
	log_info "What was verified:"
	echo "  ✓ Docker environment running (KDC + Apache proxy)"
	echo "  ✓ om CLI builds successfully"
	echo "  ✓ Test script can execute om with all required flags"
	echo "  ✓ SPNEGO flags properly rejected (as expected - not yet implemented)"
	echo ""
	log_info "Next steps:"
	echo "  1. Implement SPNEGO support in om CLI"
	echo "  2. Add --proxy-username, --proxy-password, --proxy-domain flags"
	echo "  3. Re-run this test to verify implementation"
	echo ""
	exit 0
else
	log_error "═══════════════════════════════════════════════════════════════"
	log_error "UNEXPECTED RESULT"
	log_error "═══════════════════════════════════════════════════════════════"
	echo ""
	log_info "Expected to see 'unknown flag' error for SPNEGO flags"
	log_info "but got something different. Output saved to /tmp/om-spnego-output.log"
	echo ""
	log_info "If SPNEGO support has already been implemented, this is actually good!"
	log_info "The test script will need to be updated for the next phase of testing."
	echo ""
	exit 1
fi


