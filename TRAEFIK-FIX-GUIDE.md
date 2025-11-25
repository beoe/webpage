# Quick Fix Guide: Traefik Configuration for Large Docker Image Uploads

## The Problem
Docker image uploads (especially large ones like lighthouse ~1.2GB) are failing through Traefik, even though you've set Traefik parameters.

## Most Common Issue: Missing Entrypoint Timeouts

**The #1 issue is missing entrypoint timeouts in Traefik's static configuration.**

Even if you've set middleware with `maxRequestBodyBytes`, Traefik will still timeout if the entrypoint timeouts are too short.

### Where to Fix It

You need to configure **TWO places** in Traefik:

1. **Static Configuration** (`traefik.yml`) - Entrypoint timeouts ⚠️ **OFTEN MISSED**
2. **Dynamic Configuration** (labels or dynamic files) - Middleware body size limits

## Step-by-Step Fix

### Step 1: Fix Traefik Static Config (traefik.yml)

Find your Traefik static configuration file (usually `/etc/traefik/traefik.yml` or in your Docker volume).

Add or update the `entryPoints` section:

```yaml
entryPoints:
  websecure:
    address: ":443"
    # CRITICAL: These timeouts MUST be set for large uploads
    transport:
      respondingTimeouts:
        readTimeout: 30m      # Allow 30+ minutes for large uploads
        writeTimeout: 30m     # Allow time for responses  
        idleTimeout: 5m       # Keep connection alive during slow uploads
```

**Why this matters:** Docker Registry v2 uses chunked uploads that can take 10-30 minutes for large images. Default Traefik timeouts are often only seconds or minutes, causing the connection to be closed mid-upload.

### Step 2: Verify Middleware Configuration

Check that your registry middleware has large body size limits:

**If using Docker labels:**
```yaml
- "traefik.http.middlewares.registry-body.buffering.maxRequestBodyBytes=2147483648"  # 2GB
- "traefik.http.middlewares.registry-body.buffering.maxResponseBodyBytes=2147483648"  # 2GB
- "traefik.http.routers.registry.middlewares=registry-body"
```

**If using dynamic config file:**
```yaml
http:
  middlewares:
    registry-body:
      buffering:
        maxRequestBodyBytes: 2147483648   # 2GB
        maxResponseBodyBytes: 2147483648 # 2GB
```

### Step 3: Restart Traefik

After making changes:

```bash
# If Traefik in Docker
docker restart traefik

# If Traefik as systemd service
sudo systemctl restart traefik

# Or reload if supported
docker exec traefik kill -HUP 1
```

### Step 4: Verify Configuration

Check that your changes are applied:

```bash
# Check entrypoint configuration
docker exec traefik cat /etc/traefik/traefik.yml | grep -A 15 "websecure:"

# Check middleware configuration
docker logs traefik 2>&1 | grep -i "registry\|middleware" | tail -20

# Test registry connectivity
curl -I https://registry.dockerbuch.info/v2/
```

## Common Error Messages and What They Mean

| Error | Cause | Fix |
|-------|-------|-----|
| `413 Request Entity Too Large` | Body size limit too small | Increase `maxRequestBodyBytes` in middleware |
| `504 Gateway Timeout` | Upload timeout | Increase `readTimeout` in entrypoint config |
| `context canceled` (in Traefik logs) | Request timeout | Increase entrypoint `readTimeout` to 30m+ |
| `connection reset` | Network/proxy timeout | Check both entrypoint timeouts AND buffer settings |
| `EOF` or `unexpected EOF` | Connection closed mid-upload | Increase `idleTimeout` and `readTimeout` |

## Complete Example Configuration

See `traefik-registry-config-example.yml` for complete examples of all three configuration methods.

## Testing

After applying fixes, test with:

```bash
# Run the diagnostic script
./diagnose-registry-upload.sh

# Try pushing the image
docker push registry.dockerbuch.info/dockerbuch/webpage/lighthouse:latest
```

## Still Not Working?

1. **Check Traefik logs during upload:**
   ```bash
   docker logs traefik -f | grep -i "registry\|413\|timeout\|body"
   ```

2. **Check GitLab registry logs:**
   ```bash
   sudo gitlab-ctl tail registry | grep -i "error\|413\|timeout"
   ```

3. **Verify GitLab registry max upload size:**
   ```bash
   sudo cat /etc/gitlab/gitlab.rb | grep -i "max_upload_size"
   # Should be: registry['max_upload_size'] = 10737418240  # 10GB
   ```

4. **Check network between Traefik and GitLab:**
   - Ensure Traefik can reach GitLab registry on port 5000
   - Check for firewall rules blocking connections
   - Verify DNS resolution

## Key Takeaways

✅ **Entrypoint timeouts in static config are CRITICAL** - don't skip this step!
✅ **Both static AND dynamic config must be correct**
✅ **30 minutes timeout is recommended** for large images (1GB+)
✅ **2GB body size limit** is recommended for safety margin
✅ **Restart Traefik** after making changes

