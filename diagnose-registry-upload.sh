#!/bin/bash
# Diagnostic script for Docker registry upload issues through Traefik
# Run this script to check your Traefik and GitLab registry configuration

set -e

REGISTRY="${REGISTRY:-registry.dockerbuch.info}"
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_NC='\033[0m' # No Color

echo "=========================================="
echo "Docker Registry Upload Diagnostic Tool"
echo "=========================================="
echo ""

# Test 1: Basic connectivity
echo "1. Testing registry connectivity..."
if curl -s -I "https://${REGISTRY}/v2/" | head -1 | grep -q "200\|401"; then
    echo -e "${COLOR_GREEN}✓ Registry is reachable${COLOR_NC}"
else
    echo -e "${COLOR_RED}✗ Cannot reach registry${COLOR_NC}"
    echo "   Check DNS and network connectivity"
fi
echo ""

# Test 2: Check for 413 error on upload initiation
echo "2. Testing upload endpoint (checking for 413 errors)..."
UPLOAD_TEST=$(curl -s -w "\n%{http_code}" -X POST "https://${REGISTRY}/v2/dockerbuch/webpage/lighthouse/blobs/uploads/" \
    -H "Authorization: Bearer $(docker login -u gitlab-ci-token -p ${CI_JOB_TOKEN:-test} ${REGISTRY} 2>&1 | grep -o 'WARNING.*' || echo '')" \
    2>&1 | tail -1)
if [ "$UPLOAD_TEST" = "202" ] || [ "$UPLOAD_TEST" = "401" ]; then
    echo -e "${COLOR_GREEN}✓ Upload endpoint accessible (HTTP $UPLOAD_TEST)${COLOR_NC}"
elif [ "$UPLOAD_TEST" = "413" ]; then
    echo -e "${COLOR_RED}✗ 413 Request Entity Too Large detected!${COLOR_NC}"
    echo "   This indicates Traefik body size limit is too small"
    echo "   Fix: Increase maxRequestBodyBytes in Traefik middleware"
else
    echo -e "${COLOR_YELLOW}⚠ Upload endpoint returned HTTP $UPLOAD_TEST${COLOR_NC}"
fi
echo ""

# Test 3: Check Docker client timeout
echo "3. Checking Docker client timeout..."
if [ -n "$DOCKER_CLIENT_TIMEOUT" ]; then
    echo -e "${COLOR_GREEN}✓ DOCKER_CLIENT_TIMEOUT is set to ${DOCKER_CLIENT_TIMEOUT}s${COLOR_NC}"
    if [ "$DOCKER_CLIENT_TIMEOUT" -lt 1800 ]; then
        echo -e "${COLOR_YELLOW}⚠ Warning: Timeout is less than 30 minutes (1800s)${COLOR_NC}"
        echo "   For large images, consider setting to 1800s or higher"
    fi
else
    echo -e "${COLOR_YELLOW}⚠ DOCKER_CLIENT_TIMEOUT is not set${COLOR_NC}"
    echo "   Consider setting: export DOCKER_CLIENT_TIMEOUT=1800"
fi
echo ""

# Test 4: Check if we can get Traefik configuration (if accessible)
echo "4. Traefik Configuration Check..."
echo "   (Run these commands on your Traefik server)"
echo ""
echo "   a) Check entrypoint timeouts:"
echo "      docker exec traefik cat /etc/traefik/traefik.yml 2>/dev/null | grep -A 10 'websecure:' || echo '      (Cannot access Traefik config)'"
echo ""
echo "   b) Check Traefik logs for registry errors:"
echo "      docker logs traefik 2>&1 | grep -i 'registry\\|413\\|timeout\\|body' | tail -20"
echo ""
echo "   c) Check if registry middleware is configured:"
echo "      docker exec traefik wget -qO- http://localhost:8080/api/http/middlewares 2>/dev/null | grep -i registry || echo '      (Cannot access Traefik API)'"
echo ""

# Test 5: Check image size
echo "5. Checking local lighthouse image size..."
if docker images | grep -q "lighthouse"; then
    IMAGE_SIZE=$(docker images --format "{{.Size}}" $(docker images | grep lighthouse | head -1 | awk '{print $1":"$2}') 2>/dev/null || echo "unknown")
    echo "   Lighthouse image size: $IMAGE_SIZE"
    
    # Try to extract numeric size for comparison
    SIZE_GB=$(echo "$IMAGE_SIZE" | sed 's/GB//' | awk '{print $1}')
    if [ -n "$SIZE_GB" ] && [ "$(echo "$SIZE_GB > 1.0" | bc 2>/dev/null || echo 0)" = "1" ]; then
        echo -e "${COLOR_YELLOW}⚠ Image is larger than 1GB - ensure Traefik maxRequestBodyBytes >= 2GB${COLOR_NC}"
    fi
else
    echo "   No lighthouse image found locally"
fi
echo ""

# Test 6: Recommendations
echo "=========================================="
echo "Configuration Checklist"
echo "=========================================="
echo ""
echo "Traefik Static Config (traefik.yml):"
echo "  [ ] entryPoints.websecure.transport.respondingTimeouts.readTimeout = 30m"
echo "  [ ] entryPoints.websecure.transport.respondingTimeouts.writeTimeout = 30m"
echo "  [ ] entryPoints.websecure.transport.respondingTimeouts.idleTimeout = 5m"
echo ""
echo "Traefik Middleware (labels or dynamic config):"
echo "  [ ] maxRequestBodyBytes >= 2147483648 (2GB)"
echo "  [ ] maxResponseBodyBytes >= 2147483648 (2GB)"
echo "  [ ] memRequestBodyBytes = 10485760 (10MB)"
echo ""
echo "GitLab Registry:"
echo "  [ ] registry['max_upload_size'] >= 10737418240 (10GB) in /etc/gitlab/gitlab.rb"
echo ""
echo "CI Configuration:"
echo "  [ ] DOCKER_CLIENT_TIMEOUT >= 1800 (30 minutes)"
echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Review traefik-registry-config-example.yml for complete configuration"
echo "2. Apply Traefik configuration changes"
echo "3. Restart Traefik: docker restart traefik"
echo "4. Re-run this diagnostic script"
echo "5. Try pushing the lighthouse image again"
echo ""

