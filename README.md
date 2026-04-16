# Social Media Automator

A Rails application for automating social media content planning and publishing.

## Requirements

- Ruby 3.2.2
- Node.js 20+
- Yarn
- SQLite 3

## Development Setup

```bash
# Install dependencies
bundle install
yarn install

# Set up the database
bin/rails db:prepare

# Start the development server
bin/dev
```

## Testing

```bash
# Run all tests
bin/rails test

# Run system tests
bin/rails test:system
```

## Security Checks

```bash
# Run Brakeman security scanner
bin/brakeman

# Check for vulnerable dependencies
bin/bundler-audit
```

## Deployment

This application uses [Kamal](https://kamal-deploy.org/) for deployment to Digital Ocean.

**Quick Start:**

```bash
# First-time setup
bin/deploy setup

# Regular deployments
bin/deploy deploy

# View logs
bin/deploy logs
```

For detailed deployment instructions, see [DEPLOYMENT.md](DEPLOYMENT.md).

## Environment Variables

| Variable | Description |
|----------|-------------|
| `RAILS_MASTER_KEY` | Master key for decrypting credentials |
| `KAMAL_REGISTRY_PASSWORD` | Docker registry access token |
| `SOLID_QUEUE_IN_PUMA` | Run Solid Queue in Puma process (default: true) |

## Architecture

- **Database**: SQLite (with Solid Cache, Solid Queue, Solid Cable)
- **Background Jobs**: Solid Queue
- **Asset Pipeline**: Propshaft + Import Maps
- **CSS**: CSS Bundling with Tailwind
- **File Storage**: DigitalOcean Spaces (S3-compatible)
