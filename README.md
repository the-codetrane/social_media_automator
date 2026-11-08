# Social Media Automator

A Rails application for planning, generating, and publishing social media content. It lets an admin draft posts, attach media from a shared library, get AI help with captions and images, and publish to several platforms from one place.

## Features

- **Post planning**: planned posts, reusable social templates, and published-post tracking
- **Multi-platform publishing**: Instagram, Facebook, TikTok (with a sandbox/production toggle), and YouTube
- **AI assistance**: Claude-powered chat and image understanding through RubyLLM, with prompt caching and API usage reporting
- **Media library**: uploads stored in DigitalOcean Spaces, with duplicate-import protection and archiving
- **Admin tools**: Rails 8 authentication and an admin panel for user management

## Requirements

- Ruby 3.2.2
- Node.js 24+
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

### Local LLM for the chat (optional)

In development, the chat agent can run against a local model instead of Anthropic, so working on the chat flow costs nothing. Any server that speaks the Anthropic Messages API works; the reference setup is llama.cpp serving Qwen3-Coder-Next:

```bash
# Terminal 1: start the model server (first run downloads ~73 GB)
llama-server -hf unsloth/Qwen3-Coder-Next-GGUF:UD-Q6_K_XL --alias qwen-local --jinja \
  -c 131072 --temp 1.0 --top-p 0.95 --top-k 40 --min-p 0.01 --port 8080

# Terminal 2: start the app pointed at it
LOCAL_LLM_URL=http://127.0.0.1:8080 bin/dev
```

While `LOCAL_LLM_URL` is set, the model picker shows only **Local Qwen**, and an existing chat is moved onto it (and back to your chosen Claude model when you restart without the variable). Usage still lands in the LLM costs page, priced at $0.

| Variable | Description |
|----------|-------------|
| `LOCAL_LLM_URL` | Base URL of the local server. Turns local mode on in development only; ignored in test and production. |
| `LOCAL_LLM_MODEL` | Model name the server answers to (llama-server's `--alias`). Default: `qwen-local` |
| `LOCAL_LLM_API_KEY` | Only needed if the server was started with `--api-key`. |

Image understanding (the Vision services) still uses Anthropic, since the local model is text-only.

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
