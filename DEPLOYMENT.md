# Deployment Guide - Social Media Automator

This guide walks you through deploying the Social Media Automator application to a Digital Ocean droplet using Kamal.

## Prerequisites

### 1. Local Machine Requirements
- Docker installed and running
- Ruby 3.2.2+ with Bundler
- SSH key added to your Digital Ocean droplet

### 2. Digital Ocean Droplet Requirements
- Ubuntu 22.04 LTS (recommended)
- Minimum 1GB RAM (2GB+ recommended)
- Docker will be installed automatically by Kamal

### 3. Container Registry
You'll need a container registry to store your Docker images. Options:
- **GitHub Container Registry (ghcr.io)** - Recommended
- **Docker Hub (docker.io)**
- **Digital Ocean Container Registry (registry.digitalocean.com)**

## Initial Setup

### Step 1: Configure Your Droplet IP

Edit `config/deploy.yml` and replace the placeholder IP with your actual droplet IP:

```yaml
servers:
  web:
    hosts:
      - YOUR_ACTUAL_DROPLET_IP  # e.g., 164.92.xxx.xxx
```

### Step 2: Configure Your Domain

Update the proxy settings in `config/deploy.yml`:

```yaml
proxy:
  ssl: true
  host: your-actual-domain.com  # e.g., socialmedia.mycompany.com
```

### Step 3: Configure Container Registry

Update the registry settings in `config/deploy.yml`:

**For GitHub Container Registry (recommended):**
```yaml
image: ghcr.io/your-github-username/social_media_automator

registry:
  server: ghcr.io
  username: your-github-username
  password:
    - KAMAL_REGISTRY_PASSWORD
```

**For Docker Hub:**
```yaml
image: your-dockerhub-username/social_media_automator

registry:
  server: docker.io
  username: your-dockerhub-username
  password:
    - KAMAL_REGISTRY_PASSWORD
```

### Step 4: Set Environment Variables

Create a registry access token:

**For GitHub:**
1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Create a new token with `write:packages` and `read:packages` scopes
3. Set the environment variable:
   ```bash
   export KAMAL_REGISTRY_PASSWORD=ghp_your_github_token_here
   ```

**For Docker Hub:**
1. Go to Docker Hub → Account Settings → Security → Access Tokens
2. Create a new access token
3. Set the environment variable:
   ```bash
   export KAMAL_REGISTRY_PASSWORD=your_docker_hub_token
   ```

### Step 5: Ensure master.key Exists

The `config/master.key` file must exist and should NOT be committed to git.

If you don't have it, you can regenerate credentials:
```bash
EDITOR="code --wait" bin/rails credentials:edit
```

### Step 6: Configure DNS

Point your domain to your Digital Ocean droplet IP address:
- Create an A record pointing to your droplet's IP
- Wait for DNS propagation (usually 5-30 minutes)

## Deployment Commands

### First-Time Setup

Run the initial setup to bootstrap your server:

```bash
bin/deploy setup
```

This will:
- Install Docker on your droplet
- Pull and run your application container
- Set up the proxy with SSL (Let's Encrypt)
- Run database migrations

#### Allow browser uploads to Spaces (one time per bucket)

Media Assets upload straight from the browser to DigitalOcean Spaces, so the
bucket needs a CORS rule permitting `PUT` from the app's domain. Without it the
preflight is rejected with `403 AccessDenied`, the upload never leaves the
browser, and the only server-side trace is a successful
`POST /media_assets/direct_uploads` with no `POST /media_assets` after it.

```bash
bin/kamal app exec --reuse 'bin/rails spaces:cors'
```

Pass `ORIGINS` to allow something other than the production domain:

```bash
bin/kamal app exec --reuse 'ORIGINS=https://staging.example.com bin/rails spaces:cors'
```

This is bucket state rather than application config, so it survives deploys but
must be re-run if the bucket is ever recreated or its CORS rules are reset.

### Regular Deployments

For subsequent deployments:

```bash
bin/deploy deploy
```

Or using Kamal directly:

```bash
bin/kamal deploy
```

### Other Useful Commands

```bash
# View application logs
bin/deploy logs

# Open Rails console on production server
bin/deploy console

# Open a shell on the server
bin/deploy shell

# Check application status
bin/deploy status

# Rollback to previous version
bin/deploy rollback
```

## Production Environment Configuration

### Environment Variables

Add any additional secrets to your Rails credentials:

```bash
EDITOR="code --wait" bin/rails credentials:edit
```

Example credentials structure:
```yaml
secret_key_base: your_secret_key_base

instagram:
  client_id: your_instagram_client_id
  client_secret: your_instagram_client_secret

digitalocean_spaces:
  access_key_id: your_spaces_access_key
  secret_access_key: your_spaces_secret_key
  region: nyc3
  bucket: your-bucket-name
  endpoint: https://nyc3.digitaloceanspaces.com
```

### Environment Variables in deploy.yml

For non-secret configuration, add to `config/deploy.yml`:

```yaml
env:
  secret:
    - RAILS_MASTER_KEY
  clear:
    SOLID_QUEUE_IN_PUMA: true
    RAILS_LOG_LEVEL: info
    # Add your non-secret env vars here
```

## Troubleshooting

### SSH Connection Issues

Ensure you can SSH to your droplet:
```bash
ssh root@YOUR_DROPLET_IP
```

If not, add your SSH key:
```bash
ssh-copy-id root@YOUR_DROPLET_IP
```

### Container Registry Authentication

Test registry login:
```bash
echo $KAMAL_REGISTRY_PASSWORD | docker login ghcr.io -u your-username --password-stdin
```

### View Container Logs

```bash
bin/kamal app logs
```

### Check Container Status

```bash
bin/kamal app details
```

### Database Issues

Run migrations manually:
```bash
bin/kamal app exec 'bin/rails db:migrate'
```

### SSL Certificate Issues

SSL certificates are automatically provisioned by Let's Encrypt through Kamal's proxy (Thruster). If you have issues:

1. Ensure your domain DNS is properly configured
2. Check that port 80 and 443 are open on your droplet
3. View proxy logs: `bin/kamal proxy logs`

### Restart Application

```bash
bin/kamal app boot
```

## Backup & Recovery

### Database Backup

The SQLite database is stored in a Docker volume at `/rails/storage`. To backup:

```bash
# SSH into the server
ssh root@YOUR_DROPLET_IP

# Copy the database file
docker cp $(docker ps -q -f name=social_media_automator-web):/rails/storage/production.sqlite3 ./backup.sqlite3
```

### Restore Database

```bash
# Copy backup to server
scp backup.sqlite3 root@YOUR_DROPLET_IP:~/

# SSH in and restore
ssh root@YOUR_DROPLET_IP
docker cp ~/backup.sqlite3 $(docker ps -q -f name=social_media_automator-web):/rails/storage/production.sqlite3
```

## Security Checklist

- [ ] `config/master.key` is NOT in git
- [ ] Strong SSH keys are used (Ed25519 recommended)
- [ ] Firewall is configured (only 22, 80, 443 open)
- [ ] SSL is enabled in `config/deploy.yml`
- [ ] `force_ssl` is enabled in `config/environments/production.rb`
- [ ] Registry password is stored securely (not in plain text)

## Scaling (Future)

To add more servers, update `config/deploy.yml`:

```yaml
servers:
  web:
    hosts:
      - 164.92.xxx.xxx
      - 164.92.yyy.yyy
  job:
    hosts:
      - 164.92.zzz.zzz
    cmd: bin/jobs
```

Note: When using multiple web servers, you'll need to:
1. Set up a load balancer
2. Use a centralized database (PostgreSQL recommended)
3. Use Redis/Valkey for caching and Action Cable

