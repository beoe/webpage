# Checking GitLab Registry and Traefik Configuration

## 1. Check GitLab Registry Configuration

### Check registry settings in GitLab

#### If using GitLab Omnibus (most common):
```bash
# SSH into your GitLab server
ssh user@gitlab-server

# Check current registry configuration
sudo cat /etc/gitlab/gitlab.rb | grep -i registry

# Key settings to check/modify in /etc/gitlab/gitlab.rb:
# registry['max_upload_size'] = 10737418240  # 10GB in bytes (default is usually 10GB)
# registry['client_max_body_size'] = 10737418240  # nginx setting

# After modifying, reconfigure GitLab:
sudo gitlab-ctl reconfigure
sudo gitlab-ctl restart registry
```

#### If using GitLab Helm/Kubernetes:
```bash
# Check registry values
helm get values gitlab | grep -i registry

# Key values to check:
# registry.maxUploadSize: "10737418240"  # 10GB
```

#### Check actual registry config file:
```bash
# The registry reads from:
sudo cat /var/opt/gitlab/registry/config.yml

# Look for these settings:
# storage:
#   maxuploadsize: 10737418240
```

### Check registry logs
```bash
# On GitLab server, check registry logs
sudo gitlab-ctl tail registry
# or
docker logs gitlab-registry
```

## 2. Check Traefik Configuration

Traefik has default limits that can block large uploads:

### Common Traefik limits:
- **Default body size**: Often 0 (unlimited) or 10MB
- **Need to set**: `clientMaxBodySize` or `maxRequestBodySize`

### Check Traefik configuration:

#### If using Traefik labels (Docker Compose):
```yaml
services:
  gitlab-registry:
    # ... your registry config ...
    labels:
      # Create middleware for large body size
      - "traefik.http.middlewares.registry-body.buffering.maxRequestBodyBytes=2147483648"  # 2GB
      # Apply middleware to registry router
      - "traefik.http.routers.registry.middlewares=registry-body"
      # Or if using entrypoint directly:
      - "traefik.http.routers.registry.rule=Host(`registry.dockerbuch.info`)"
      - "traefik.http.routers.registry.entrypoints=websecure"
      - "traefik.http.routers.registry.tls.certresolver=letsencrypt"
      - "traefik.http.routers.registry.middlewares=registry-body"
```

**Important**: The value is in **bytes**. Examples:
- 1GB = 1073741824
- 2GB = 2147483648 (recommended for 1.2GB images)
- 5GB = 5368709120

#### If using Traefik static config (traefik.yml):
```yaml
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

# Add to your registry service
http:
  middlewares:
    registry-body:
      buffering:
        maxRequestBodyBytes: 2147483648  # 2GB
```

#### If using Traefik dynamic config:
```yaml
# In your dynamic config file
http:
  middlewares:
    registry-body:
      buffering:
        maxRequestBodyBytes: 2147483648  # 2GB
```

## 3. Test Registry Upload Limits

### Test with a small image first:
```bash
# Test basic connectivity
curl -I https://registry.dockerbuch.info/v2/

# Test authentication
docker login registry.dockerbuch.info
```

### Test with actual push and monitor:
```bash
# Push with verbose output to see where it fails
docker push registry.dockerbuch.info/dockerbuch/webpage/lighthouse:test 2>&1 | tee push.log

# Check for specific errors:
# - 413 Request Entity Too Large (Traefik/nginx limit)
# - 504 Gateway Timeout (timeout issue)
# - Connection reset (network/proxy issue)
```

## 4. Check HTTP Headers

### Test what limits are being returned:
```bash
# Check what the registry reports
curl -I -X POST https://registry.dockerbuch.info/v2/dockerbuch/webpage/lighthouse/blobs/uploads/

# Look for headers like:
# - Content-Length
# - X-Request-Id
# - Docker-Distribution-Api-Version
```

## 5. Common Issues and Solutions

### Issue: 413 Request Entity Too Large
**Cause**: Traefik or nginx body size limit
**Solution**: Increase `clientMaxBodySize` in Traefik

### Issue: 504 Gateway Timeout
**Cause**: Upload takes longer than proxy timeout
**Solution**: Increase timeout settings in Traefik:
```yaml
http:
  services:
    registry:
      loadBalancer:
        servers:
          - url: "http://gitlab-registry:5000"
        passHostHeader: true
        responseForwarding:
          flushInterval: 100ms
```

### Issue: Connection reset during upload
**Cause**: Network timeout or proxy buffer issues
**Solution**: Increase buffer sizes and timeouts in Traefik:
```yaml
http:
  middlewares:
    registry-body:
      buffering:
        maxRequestBodyBytes: 2147483648  # 2GB
        maxResponseBodyBytes: 2147483648  # 2GB
        memRequestBodyBytes: 10485760  # 10MB buffer
```

### Issue: "context canceled" error in Traefik logs
**Error**: `vulcand/oxy/buffer: error when reading request body, err: context canceled`
**Cause**: Request timeout - Traefik or client is canceling the request before upload completes
**Solution**: Increase Traefik entrypoint timeouts:
```yaml
# In traefik.yml (static config)
entryPoints:
  websecure:
    address: ":443"
    transport:
      respondingTimeouts:
        readTimeout: 30m      # Critical: Allow 30+ minutes for large uploads
        writeTimeout: 30m     # Allow time for responses
        idleTimeout: 5m       # Keep connection alive during slow uploads
```

**Also check Docker client timeout** (in CI or Docker daemon config):
```bash
# In CI, set Docker client timeout
export DOCKER_CLIENT_TIMEOUT=1800  # 30 minutes
# or in docker daemon.json
{
  "max-concurrent-uploads": 5,
  "max-concurrent-downloads": 5
}
```

## 6. Quick Diagnostic Commands

### Test registry with curl:
```bash
# Test basic connectivity
curl -v "https://registry.dockerbuch.info/v2/"

# Test with authentication (replace with your token)
TOKEN="your-gitlab-token"
curl -H "Authorization: Bearer $TOKEN" "https://registry.dockerbuch.info/v2/dockerbuch/webpage/lighthouse/tags/list"
```

### Check GitLab registry configuration (on GitLab server):
```bash
# If using GitLab Omnibus
sudo gitlab-ctl show-config | grep -i registry
sudo cat /var/opt/gitlab/registry/config.yml | grep -i "max\|size\|limit"

# Check registry logs for errors
sudo gitlab-ctl tail registry | grep -i "error\|413\|504\|timeout"
```

### Check Traefik logs:
```bash
# If Traefik in Docker
docker logs traefik 2>&1 | grep -i "registry\|413\|timeout\|body"

# If Traefik as service
journalctl -u traefik -f | grep -i "registry\|413\|timeout"
```

## 7. Complete Traefik Example for Registry

Here's a complete example for configuring Traefik to handle large registry uploads:

### Option A: Using Docker Labels (Recommended)
```yaml
# docker-compose.yml or your GitLab registry service
services:
  gitlab-registry:
    image: registry:2
    labels:
      # Router configuration
      - "traefik.enable=true"
      - "traefik.http.routers.registry.rule=Host(`registry.dockerbuch.info`)"
      - "traefik.http.routers.registry.entrypoints=websecure"
      - "traefik.http.routers.registry.tls.certresolver=letsencrypt"
      
      # Middleware for large uploads with increased timeouts
      - "traefik.http.middlewares.registry-body.buffering.maxRequestBodyBytes=2147483648"  # 2GB
      - "traefik.http.middlewares.registry-body.buffering.maxResponseBodyBytes=2147483648"  # 2GB
      - "traefik.http.middlewares.registry-body.buffering.memRequestBodyBytes=10485760"  # 10MB
      - "traefik.http.middlewares.registry-body.buffering.retryExpression=IsNetworkError() && Attempts() < 3"
      
      # Apply middleware
      - "traefik.http.routers.registry.middlewares=registry-body"
      
      # Service configuration with increased timeouts
      - "traefik.http.services.registry.loadbalancer.server.port=5000"
      - "traefik.http.services.registry.loadbalancer.healthCheck.interval=30s"
      - "traefik.http.services.registry.loadbalancer.healthCheck.timeout=10s"
```

**Important**: Also configure Traefik entrypoint timeouts in your Traefik static config:
```yaml
# In traefik.yml or static config
entryPoints:
  websecure:
    address: ":443"
    transport:
      respondingTimeouts:
        readTimeout: 30m      # Allow 30 minutes for large uploads
        writeTimeout: 30m     # Allow 30 minutes for responses
        idleTimeout: 5m       # Keep connection alive
```

### Option B: Using Dynamic Configuration File
```yaml
# traefik/dynamic/registry.yml
http:
  middlewares:
    registry-body:
      buffering:
        maxRequestBodyBytes: 2147483648  # 2GB
        maxResponseBodyBytes: 2147483648  # 2GB
        memRequestBodyBytes: 10485760  # 10MB

  routers:
    registry:
      rule: "Host(`registry.dockerbuch.info`)"
      entryPoints:
        - websecure
      middlewares:
        - registry-body
      service: registry
      tls:
        certResolver: letsencrypt

  services:
    registry:
      loadBalancer:
        servers:
          - url: "http://gitlab-registry:5000"
        passHostHeader: true
```

### After making changes:
```bash
# Reload Traefik (if using file-based config)
docker exec traefik kill -HUP 1
# or restart Traefik
docker restart traefik
# or
systemctl reload traefik
```
