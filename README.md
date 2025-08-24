# 🚀 CLIDEHOOK - The CLIDE Execution Engine

> Transform GitHub issues into fully implemented features through autonomous development

## Overview

CLIDEHOOK is the execution engine for [CLIDE (CLI IDE)](OVERVIEW.md), an autonomous software development system that turns GitHub issues into production-ready code. It orchestrates specialized AI agents to handle planning, implementation, documentation, and testing - all while maintaining your team's standards and conventions.

## 🎯 Key Features

- **Complete Autonomy** - Handles the entire development lifecycle from issue to merged PR
- **Specialized Sub-Agents** - Dedicated agents for planning, coding, documenting, and testing
- **GitHub-Native** - Communicates entirely through issues, PRs, and comments
- **Video Integration** - Creates PRs with Playwright video demos and auto-play GIFs
- **Self-Improving** - Learns from your codebase and adapts to your patterns
- **Production-Ready** - Handles real-world development with proper error handling and recovery

## 🏗️ Architecture

CLIDEHOOK integrates with two companion systems:

```
GitHub → HLS → DECK → CLIDEHOOK
         ↓      ↓         ↓
      Webhooks Queue  Execution
```

- **[HLS (Hook Line Sinker)](https://github.com/clidecoder/hook-line-sinker)** - Receives and validates webhooks
- **[DECK](https://github.com/clidecoder/deck)** - Manages queue and concurrency
- **CLIDEHOOK** - Executes autonomous development

## 📚 Documentation

- [**Integration Guide**](docs/INTEGRATION.md) - Complete integration architecture
- [**Webhook Events**](docs/WEBHOOK-EVENTS.md) - Detailed event reference
- [**Deployment Guide**](docs/DEPLOYMENT-GUIDE.md) - Production deployment instructions
- [**Prompt Templates**](docs/PROMPT-TEMPLATES.md) - AI agent prompt customization
- [**PR Video Integration**](docs/PR-VIDEO-INTEGRATION.md) - Playwright video demos in PRs

## 🚦 Quick Start

### Prerequisites

- Ubuntu 20.04+ or similar Linux distribution
- Git 2.30+ (with worktree support)
- Node.js 18+ and npm
- tmux 3.0+
- Claude Code CLI (authenticated)
- GitHub personal access token

### Basic Installation

```bash
# Clone the repository
git clone https://github.com/clidecoder/clidehook.git
cd clidehook

# Install dependencies
npm install

# Configure environment
cp .env.example .env
# Edit .env with your configuration

# Test the installation
./clidehook test
```

### Repository Setup

1. Add `claude.md` to your repository:
```markdown
# claude.md

## Project Standards
- Language: TypeScript
- Testing: Jest
- Style: ESLint + Prettier

## CLIDE Instructions
- Always write tests
- Update README for new features
- Use conventional commits
```

2. Configure webhook in GitHub:
   - Go to Settings → Webhooks → Add webhook
   - URL: `https://your-hls-instance/webhook/org/repo`
   - Secret: Your webhook secret
   - Events: Issues, Pull requests, Issue comments

3. Create an issue and watch CLIDE work!

## 🎭 How It Works

### 1. Issue Created
When you open an issue, CLIDE:
- Sets up an isolated development environment
- Analyzes requirements
- Creates an implementation plan
- Asks clarifying questions if needed

### 2. Human Interaction
CLIDE uses a simple prefix system:
- **CLIDE:** - Messages from CLIDE
- **No prefix** - Human messages

Example:
```
Human: "Please add user authentication with OAuth2"
CLIDE: Planning complete. I'll implement OAuth2 authentication with:
- GitHub provider support
- JWT token management
- Protected route middleware
```

### 3. Implementation
CLIDE works through specialized agents:
- **Planning Agent** - Analyzes and plans
- **Implementation Agent** - Writes code
- **Documentation Agent** - Updates docs
- **Testing Agent** - Creates tests

### 4. Pull Request
CLIDE creates a PR with:
- Clear description linking to the issue
- Atomic commits with good messages
- Inline comments explaining decisions
- All tests passing

### 5. Review & Merge
- Humans review the PR
- CLIDE responds to feedback
- Makes requested changes
- PR gets merged

## 🛠️ Configuration

### Environment Variables

```bash
# Required
GITHUB_TOKEN=ghp_xxxxxxxxxxxx
CLAUDE_API_KEY=sk-ant-xxxxxxxxxxxx
WEBHOOK_SECRET=your-webhook-secret

# Optional
CLIDE_HOME=/var/clide
MAX_CONCURRENT_SESSIONS=3
DEFAULT_BRANCH=main
```

### Advanced Configuration

See [claude.md](claude.md.example) for detailed configuration options including:
- Coding standards
- Git conventions
- Testing requirements
- Project structure
- CLIDE-specific instructions

## 🚨 Controlling CLIDE

### Commands
- **"HALT WORK"** - Immediately stops all processing
- **"@clide-bot explain"** - Get explanation of decisions
- **"@clide-bot status"** - Check current progress

### Labels
- `halt-work` - Stops CLIDE processing
- `urgent` - Increases priority
- `needs-clarification` - CLIDE awaits response
- `ready-for-clide` - Explicitly allows CLIDE to work

## 🔍 Monitoring

### Logs
```bash
# View CLIDE logs
tail -f /var/clide/logs/clidehook/session-*.log

# Check agent activity
tail -f /var/clide/logs/agents/*.log
```

### Health Checks
```bash
# Check system status
clidehook status

# View active sessions
tmux ls | grep clide

# Check work trees
git worktree list
```

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup
```bash
# Install dev dependencies
npm install --dev

# Run tests
npm test

# Run linter
npm run lint
```

## 📝 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

CLIDEHOOK is part of the CLIDE ecosystem:
- [HLS](https://github.com/clidecoder/hook-line-sinker) - Webhook handling
- [DECK](https://github.com/clidecoder/deck) - Queue management
- [Claude Code](https://claude.ai/code) - AI platform

## 🚀 Ready to Start?

1. [Read the Integration Guide](docs/INTEGRATION.md)
2. [Follow the Deployment Guide](docs/DEPLOYMENT-GUIDE.md)
3. Create your first issue and watch CLIDE work!

---

*Transform your GitHub issues into production code - autonomously, reliably, intelligently.*