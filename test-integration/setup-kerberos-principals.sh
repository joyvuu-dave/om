#!/usr/bin/env bash
# Setup Kerberos Principals for SPNEGO Testing
# Creates test users and service principals needed for proxy authentication

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

log_step() { echo -e "${BLUE}${BOLD}$1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] ✓ $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] ✗ $1${NC}"; }
log_info() { echo -e "${BOLD}[INFO] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] ⚠ $1${NC}"; }

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                                                                    ║${NC}"
echo -e "${BOLD}║         Kerberos Principal Setup for SPNEGO Testing                ║${NC}"
echo -e "${BOLD}║                                                                    ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if KDC is running
log_step "▶ Step 1: Checking KDC Status"
echo ""

if ! docker ps --format "{{.Names}}" | grep -q "test-kerberos-kdc"; then
	log_error "Kerberos KDC container not running"
	log_info "Start with: docker-compose up -d"
	exit 1
fi
log_success "KDC container is running"

# Check if proxy is running
if ! docker ps --format "{{.Names}}" | grep -q "test-apache-proxy"; then
	log_warn "Apache proxy container not running"
	log_info "Start with: docker-compose up -d"
else
	log_success "Proxy container is running"
fi

echo ""
log_step "▶ Step 2: Creating Test User Principal"
echo ""

log_info "Creating principal: testuser@TEST.LOCAL"
if docker exec test-kerberos-kdc kadmin.local -q "addprinc -pw testpass123 testuser@TEST.LOCAL" 2>&1 | grep -q "already exists"; then
	log_warn "Principal testuser@TEST.LOCAL already exists"
else
	log_success "Created testuser@TEST.LOCAL with password: testpass123"
fi

echo ""
log_step "▶ Step 3: Creating HTTP Service Principals for Proxy"
echo ""

# The proxy needs HTTP service principals for both localhost and its container name
PRINCIPALS=(
	"HTTP/localhost"
	"HTTP/proxy.test.local"
	"HTTP/test-apache-proxy"
)

for principal in "${PRINCIPALS[@]}"; do
	log_info "Creating principal: ${principal}@TEST.LOCAL"
	if docker exec test-kerberos-kdc kadmin.local -q "addprinc -randkey ${principal}@TEST.LOCAL" 2>&1 | grep -q "already exists"; then
		log_warn "Principal ${principal}@TEST.LOCAL already exists"
	else
		log_success "Created ${principal}@TEST.LOCAL"
	fi
done

echo ""
log_step "▶ Step 4: Exporting Service Principals to Keytab"
echo ""

# Export all HTTP principals to a single keytab
log_info "Exporting principals to /tmp/proxy.keytab..."

# Remove old keytab if exists
docker exec test-kerberos-kdc rm -f /tmp/proxy.keytab 2>/dev/null || true

for principal in "${PRINCIPALS[@]}"; do
	log_info "  Adding ${principal}@TEST.LOCAL to keytab"
	docker exec test-kerberos-kdc kadmin.local -q "ktadd -k /tmp/proxy.keytab -norandkey ${principal}@TEST.LOCAL" >/dev/null 2>&1
done

log_success "Keytab created with all HTTP principals"

# Verify keytab contents
echo ""
log_info "Keytab contents:"
docker exec test-kerberos-kdc klist -kt /tmp/proxy.keytab | grep -v "^Keytab name:" || true

echo ""
log_step "▶ Step 5: Installing Keytab in Proxy Container"
echo ""

if docker ps --format "{{.Names}}" | grep -q "test-apache-proxy"; then
	# Copy keytab from KDC to proxy
	log_info "Copying keytab to proxy container..."
	docker cp test-kerberos-kdc:/tmp/proxy.keytab /tmp/proxy.keytab
	docker cp /tmp/proxy.keytab test-apache-proxy:/etc/apache2/proxy.keytab
	
	# Set correct permissions
	docker exec test-apache-proxy chown www-data:www-data /etc/apache2/proxy.keytab
	docker exec test-apache-proxy chmod 600 /etc/apache2/proxy.keytab
	
	log_success "Keytab installed in proxy container"
	
	# Restart Apache to pick up new keytab
	log_info "Restarting Apache..."
	docker exec test-apache-proxy apachectl restart 2>/dev/null || \
		docker restart test-apache-proxy >/dev/null
	
	log_success "Apache restarted"
	
	# Cleanup temp file
	rm -f /tmp/proxy.keytab
else
	log_warn "Proxy container not running - keytab not installed"
	log_info "Keytab saved on KDC at: /tmp/proxy.keytab"
fi

echo ""
log_step "▶ Step 6: Verification"
echo ""

log_info "Listing all principals in realm TEST.LOCAL:"
docker exec test-kerberos-kdc kadmin.local -q "listprincs" | grep -E "(testuser|HTTP)" || log_warn "No principals found"

echo ""
log_success "═══════════════════════════════════════════════════════════════"
log_success "🎉 Kerberos Setup Complete! 🎉"
log_success "═══════════════════════════════════════════════════════════════"
echo ""
log_info "Summary:"
echo "  ✓ Test user: testuser@TEST.LOCAL (password: testpass123)"
echo "  ✓ Service principals: HTTP/localhost, HTTP/proxy.test.local, HTTP/test-apache-proxy"
echo "  ✓ Keytab installed in proxy container"
echo ""
log_info "Next steps:"
echo "  1. Test authentication: kinit testuser@TEST.LOCAL"
echo "  2. Verify ticket: klist"
echo "  3. Run SPNEGO test: ./test-om-spnego.sh"
echo ""
log_info "Troubleshooting:"
echo "  - View KDC logs: docker logs test-kerberos-kdc"
echo "  - View proxy logs: docker logs test-apache-proxy"
echo "  - Test kinit: KRB5_CONFIG=./krb5-host.conf kinit testuser@TEST.LOCAL"
echo ""


