# CLIDE Deployment Guide

## Table of Contents
1. [System Requirements](#system-requirements)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Component Installation](#component-installation)
4. [Configuration](#configuration)
5. [Security Setup](#security-setup)
6. [Production Deployment](#production-deployment)
7. [Monitoring Setup](#monitoring-setup)
8. [Backup & Recovery](#backup--recovery)
9. [Scaling Considerations](#scaling-considerations)
10. [Troubleshooting](#troubleshooting)

## System Requirements

### Minimum Hardware Requirements
- CPU: 4 cores (8 recommended)
- RAM: 8GB (16GB recommended)
- Storage: 100GB SSD (for worktrees and logs)
- Network: Stable internet connection with GitHub access

### Software Dependencies
```bash
# Core requirements
- Ubuntu 20.04+ or Debian 11+
- Git 2.30+ (worktree support)
- Node.js 18+ and npm 9+
- Go 1.21+ (for DECK)
- tmux 3.0+
- jq 1.6+ (JSON processing)

# Claude Code CLI
- claude-code CLI authenticated and configured

# Optional but recommended
- nginx (reverse proxy)
- pm2 (process manager)
- PostgreSQL 14+ (if using advanced queue features)
- Redis 7+ (for caching)
```

### GitHub Requirements
- GitHub App or webhook access
- Personal Access Token with appropriate scopes:
  - `repo` (full repository access)
  - `write:issues` (issue management)
  - `write:pull_requests` (PR management)

## Pre-Deployment Checklist

### 1. System Preparation
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install core dependencies
sudo apt install -y git tmux jq build-essential curl wget

# Install Node.js (using NodeSource)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Install Go
wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/bin:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# Create CLIDE user and directories
sudo useradd -m -s /bin/bash clide
sudo mkdir -p /var/clide/{worktrees,logs,config,deck}
sudo chown -R clide:clide /var/clide
```

### 2. Network Configuration
```bash
# Open required ports (if using firewall)
sudo ufw allow 8080/tcp  # HLS webhook receiver
sudo ufw allow 8090/tcp  # DECK API (internal)
sudo ufw allow 22/tcp    # SSH
sudo ufw enable
```

### 3. GitHub Setup
```bash
# Configure git for CLIDE user
sudo -u clide git config --global user.name "CLIDE Bot"
sudo -u clide git config --global user.email "clide@your-domain.com"

# Setup GitHub CLI
sudo -u clide gh auth login
```

## Component Installation

### 1. Install HLS (Hook Line Sinker)
```bash
# As clide user
sudo su - clide
cd ~

# Clone HLS
git clone https://github.com/clidecoder/hook-line-sinker.git
cd hook-line-sinker

# Install dependencies
npm install

# Setup database
npm run setup-db

# Configure environment
cat > .env << EOF
PORT=8080
WEBHOOK_SECRET=your-github-webhook-secret
CLAUDE_API_KEY=your-claude-api-key
DATABASE_PATH=./hls_webhooks.db
DECK_ENDPOINT=http://localhost:8090
EOF

# Test HLS
npm test

# Setup PM2 for production
npm install -g pm2
pm2 start hls.js --name hls
pm2 save
pm2 startup
```

### 2. Install DECK
```bash
# As clide user
cd ~

# Clone DECK
git clone https://github.com/clidecoder/deck.git
cd deck

# Build DECK
go build -o deck cmd/deck/main.go

# Install binary
sudo mv deck /usr/local/bin/
sudo chmod +x /usr/local/bin/deck

# Initialize DECK
deck init

# Configure DECK
cat > /var/clide/deck/config.yaml << EOF
max_concurrent: 3
default_priority: medium
ticket_timeout: 3600
cleanup_interval: 300
worker_check_interval: 10

directories:
  queue: /var/clide/deck/queue
  active: /var/clide/deck/active
  logs: /var/clide/logs/deck

executor:
  command: /usr/local/bin/clidehook
  timeout: 7200
  environment:
    - CLIDE_HOME=/var/clide
    - PATH=/usr/local/bin:/usr/bin:/bin

repositories:
  - pattern: "*/*"
    max_concurrent: 2
    priority_boost: 0
EOF

# Start DECK worker
deck worker start

# Setup systemd service
sudo tee /etc/systemd/system/deck-worker.service << EOF
[Unit]
Description=DECK Queue Worker
After=network.target

[Service]
Type=simple
User=clide
WorkingDirectory=/var/clide
ExecStart=/usr/local/bin/deck worker start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable deck-worker
sudo systemctl start deck-worker
```

### 3. Install CLIDEHOOK
```bash
# As clide user
cd ~

# Clone CLIDEHOOK
git clone https://github.com/clidecoder/clidehook.git
cd clidehook

# Make scripts executable
chmod +x scripts/*.sh
chmod +x clidehook

# Install CLIDEHOOK
sudo cp clidehook /usr/local/bin/
sudo cp scripts/* /usr/local/bin/

# Create agent scripts
mkdir -p ~/clide-agents
cp agents/* ~/clide-agents/
chmod +x ~/clide-agents/*

# Configure Claude Code
claude-code auth login
```

## Configuration

### 1. HLS Configuration
```javascript
// ~/hook-line-sinker/config/clide.js
module.exports = {
    // Webhook filtering
    clide_events: [
        'issues.opened',
        'issues.closed',
        'issues.reopened',
        'issue_comment.created',
        'issue_comment.edited',
        'pull_request.opened',
        'pull_request.synchronize',
        'pull_request.closed',
        'pull_request_review.submitted',
        'pull_request_review_comment.created',
        'issues.labeled',
        'issues.unlabeled',
        'issues.assigned',
        'issues.unassigned'
    ],
    
    // CLIDE detection
    clide_prefix: 'CLIDE:',
    clide_bot_username: 'clide-bot',
    
    // Repository configuration
    repositories: {
        'org/repo': {
            enabled: true,
            deck_priority: 'medium',
            max_concurrent: 2,
            claude_model: 'claude-3-opus-20240229'
        }
    },
    
    // Prompt template paths
    prompt_templates: {
        planning: './prompts/repos/${repo}/clide-planning.md',
        implementation: './prompts/repos/${repo}/clide-implementation.md',
        documentation: './prompts/repos/${repo}/clide-documentation.md',
        testing: './prompts/repos/${repo}/clide-testing.md'
    }
};
```

### 2. CLIDEHOOK Configuration
```bash
# /var/clide/config/clidehook.conf
# CLIDE Hook Configuration

# Paths
CLIDE_HOME="/var/clide"
WORKTREE_BASE="/var/clide/worktrees"
LOG_BASE="/var/clide/logs/clidehook"
AGENT_DIR="/home/clide/clide-agents"

# GitHub Configuration
GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"
GITHUB_API_URL="https://api.github.com"

# Claude Configuration
CLAUDE_MODEL="claude-3-opus-20240229"
CLAUDE_MAX_TOKENS="4096"

# Tmux Configuration
TMUX_SESSION_PREFIX="clide"
TMUX_SOCKET_DIR="/var/clide/tmux"

# Behavior Configuration
AUTO_CLEANUP="true"
CLEANUP_AFTER_DAYS="7"
MAX_CLARIFICATION_WAIT="86400"  # 24 hours
DEFAULT_BRANCH="main"

# Agent Configuration
PLANNING_TIMEOUT="300"
IMPLEMENTATION_TIMEOUT="1800"
TESTING_TIMEOUT="600"
DOCUMENTATION_TIMEOUT="300"
```

### 3. Repository Configuration (claude.md)
```markdown
# claude.md - CLIDE Configuration for this Repository

## Project Overview
Brief description of the project and its purpose.

## Technology Stack
- Language: TypeScript
- Framework: React 18 with Vite
- Testing: Vitest + React Testing Library
- State Management: Zustand
- Styling: Tailwind CSS

## Development Standards

### Code Style
- Use TypeScript strict mode
- Prefer functional components with hooks
- Use named exports (no default exports)
- Keep components under 200 lines

### Git Conventions
- Branch naming: `clide/issue-{number}`
- Commit format: `type(scope): description`
- Types: feat, fix, docs, style, refactor, test, chore

### Testing Requirements
- Minimum 80% code coverage
- Test files adjacent to source: `Component.test.tsx`
- Use data-testid for E2E test reliability

### File Organization
```
src/
├── components/     # React components
├── hooks/         # Custom React hooks
├── services/      # API and external services
├── utils/         # Helper functions
├── types/         # TypeScript type definitions
└── tests/         # Test utilities and mocks
```

## CLIDE-Specific Instructions

### Always Do
- Write comprehensive tests for new features
- Update README.md when adding new functionality
- Use existing patterns found in the codebase
- Add JSDoc comments for exported functions
- Run `npm run lint` and `npm test` before committing

### Never Do
- Don't add new dependencies without justification
- Don't modify .gitignore or CI/CD configs
- Don't change existing API contracts
- Don't commit console.log statements

### When Stuck
- Look for similar patterns in existing code
- Check test files for usage examples
- Ask for clarification rather than guessing
- Mention specific files you're unsure about
```

## Security Setup

### 1. GitHub Webhook Security
```bash
# Generate webhook secret
WEBHOOK_SECRET=$(openssl rand -hex 32)
echo "Save this webhook secret: $WEBHOOK_SECRET"

# Configure in GitHub repository settings:
# Settings > Webhooks > Add webhook
# - URL: https://your-domain.com/webhook/org/repo
# - Content type: application/json
# - Secret: $WEBHOOK_SECRET
# - Events: Select individual events (see WEBHOOK-EVENTS.md)
```

### 2. Access Control
```bash
# Restrict CLIDE directories
sudo chmod 700 /var/clide
sudo chmod 700 /var/clide/worktrees
sudo chmod 755 /var/clide/logs

# Setup log rotation
sudo tee /etc/logrotate.d/clide << EOF
/var/clide/logs/*/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 clide clide
}
EOF
```

### 3. API Security
```nginx
# nginx configuration for HLS
server {
    listen 443 ssl http2;
    server_name webhooks.your-domain.com;
    
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=webhook:10m rate=10r/s;
    
    location /webhook/ {
        limit_req zone=webhook burst=20 nodelay;
        
        proxy_pass http://localhost:8080;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Hub-Signature-256 $http_x_hub_signature_256;
        
        # Only allow GitHub IPs
        allow 140.82.112.0/20;
        allow 143.55.64.0/20;
        allow 185.199.108.0/22;
        allow 192.30.252.0/22;
        deny all;
    }
}
```

## Production Deployment

### 1. Environment Variables
```bash
# Production environment file
cat > /var/clide/config/production.env << EOF
NODE_ENV=production
LOG_LEVEL=info
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
WEBHOOK_SECRET=your-webhook-secret
CLAUDE_API_KEY=your-claude-api-key
DATABASE_URL=postgresql://clide:password@localhost/clide
REDIS_URL=redis://localhost:6379
SENTRY_DSN=https://xxxx@sentry.io/xxxx
EOF
```

### 2. Process Management
```bash
# PM2 ecosystem file
cat > /home/clide/ecosystem.config.js << EOF
module.exports = {
  apps: [
    {
      name: 'hls',
      script: '/home/clide/hook-line-sinker/hls.js',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        NODE_ENV: 'production',
        PORT: 8080
      },
      error_file: '/var/clide/logs/hls/error.log',
      out_file: '/var/clide/logs/hls/out.log'
    }
  ]
};
EOF

# Start all services
pm2 start ecosystem.config.js
pm2 save
```

### 3. Health Checks
```bash
# Create health check script
cat > /usr/local/bin/clide-health-check << 'EOF'
#!/bin/bash

# Check HLS
if ! curl -s http://localhost:8080/health > /dev/null; then
    echo "ERROR: HLS is not responding"
    exit 1
fi

# Check DECK
if ! deck status > /dev/null 2>&1; then
    echo "ERROR: DECK is not running"
    exit 1
fi

# Check worktrees
WORKTREE_COUNT=$(git worktree list | grep -c clide)
echo "Active worktrees: $WORKTREE_COUNT"

# Check tmux sessions
TMUX_COUNT=$(tmux ls 2>/dev/null | grep -c clide)
echo "Active tmux sessions: $TMUX_COUNT"

echo "All systems operational"
EOF

chmod +x /usr/local/bin/clide-health-check

# Add to crontab
(crontab -l ; echo "*/5 * * * * /usr/local/bin/clide-health-check") | crontab -
```

## Monitoring Setup

### 1. Prometheus Metrics
```yaml
# prometheus.yml addition
scrape_configs:
  - job_name: 'clide-hls'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: '/metrics'
  
  - job_name: 'clide-deck'
    static_configs:
      - targets: ['localhost:8090']
    metrics_path: '/metrics'
```

### 2. Grafana Dashboard
```json
{
  "dashboard": {
    "title": "CLIDE System Dashboard",
    "panels": [
      {
        "title": "Webhook Events/min",
        "targets": [
          {
            "expr": "rate(hls_webhook_events_total[1m])"
          }
        ]
      },
      {
        "title": "Active Development Sessions",
        "targets": [
          {
            "expr": "deck_active_tickets"
          }
        ]
      },
      {
        "title": "Queue Depth",
        "targets": [
          {
            "expr": "deck_queue_length"
          }
        ]
      }
    ]
  }
}
```

### 3. Alerting Rules
```yaml
# alerts.yml
groups:
  - name: clide_alerts
    rules:
      - alert: HLSDown
        expr: up{job="clide-hls"} == 0
        for: 5m
        annotations:
          summary: "HLS webhook receiver is down"
      
      - alert: QueueBacklog
        expr: deck_queue_length > 50
        for: 15m
        annotations:
          summary: "DECK queue backlog is growing"
      
      - alert: StuckSession
        expr: deck_ticket_age_seconds > 7200
        annotations:
          summary: "Development session stuck for >2 hours"
```

## Backup & Recovery

### 1. Backup Strategy
```bash
# Daily backup script
cat > /usr/local/bin/clide-backup << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/clide/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Backup configurations
cp -r /var/clide/config "$BACKUP_DIR/"

# Backup DECK state
deck export > "$BACKUP_DIR/deck-state.json"

# Backup HLS database
sqlite3 /home/clide/hook-line-sinker/hls_webhooks.db ".backup $BACKUP_DIR/hls.db"

# Backup logs
tar -czf "$BACKUP_DIR/logs.tar.gz" /var/clide/logs/

# Rotate old backups (keep 30 days)
find /backup/clide -type d -mtime +30 -exec rm -rf {} \;
EOF

chmod +x /usr/local/bin/clide-backup
(crontab -l ; echo "0 2 * * * /usr/local/bin/clide-backup") | crontab -
```

### 2. Recovery Procedures
```bash
# Restore from backup
BACKUP_DATE="20240115"
BACKUP_DIR="/backup/clide/$BACKUP_DATE"

# Stop services
pm2 stop all
sudo systemctl stop deck-worker

# Restore configurations
cp -r "$BACKUP_DIR/config/"* /var/clide/config/

# Restore DECK state
deck import < "$BACKUP_DIR/deck-state.json"

# Restore HLS database
cp "$BACKUP_DIR/hls.db" /home/clide/hook-line-sinker/hls_webhooks.db

# Restart services
sudo systemctl start deck-worker
pm2 restart all
```

## Scaling Considerations

### 1. Horizontal Scaling
```yaml
# Multiple DECK workers on different nodes
# deck-worker-2.yaml
worker_id: worker-2
redis_url: redis://redis-cluster:6379
shared_filesystem: /mnt/clide-shared
```

### 2. Load Balancing
```nginx
upstream hls_backends {
    least_conn;
    server hls-1:8080 weight=1;
    server hls-2:8080 weight=1;
    server hls-3:8080 weight=1;
}
```

### 3. Database Scaling
```sql
-- Partition HLS events table by month
CREATE TABLE webhook_events_2024_01 PARTITION OF webhook_events
FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Webhooks Not Received
```bash
# Check HLS logs
pm2 logs hls

# Verify webhook configuration
curl -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/org/repo/hooks

# Test webhook delivery
gh api repos/org/repo/hooks/HOOK_ID/test
```

#### 2. DECK Queue Stuck
```bash
# Check queue status
deck list --all

# Clear stuck ticket
deck clear org/repo 123 --force

# Restart worker
sudo systemctl restart deck-worker
```

#### 3. Tmux Session Issues
```bash
# List all CLIDE sessions
tmux ls | grep clide

# Attach to investigate
tmux attach -t clide-org-repo-123

# Kill hung session
tmux kill-session -t clide-org-repo-123
```

#### 4. Git Worktree Problems
```bash
# List worktrees
git worktree list

# Remove corrupted worktree
git worktree remove /var/clide/worktrees/org-repo-issue-123 --force

# Prune worktree references
git worktree prune
```

### Debug Mode
```bash
# Enable debug logging
export LOG_LEVEL=debug
export CLIDE_DEBUG=1

# Run CLIDEHOOK manually
/usr/local/bin/clidehook org/repo 123 '{"event_type":"issues","action":"opened"}'

# Check agent logs
tail -f /var/clide/logs/clidehook/agents/*.log
```

### Performance Tuning
```bash
# Adjust DECK concurrency
deck config set max_concurrent 5

# Increase HLS workers
pm2 scale hls 4

# Optimize git operations
git config --global core.preloadindex true
git config --global core.fscache true
git config --global gc.auto 256
```

## Maintenance Tasks

### Weekly Maintenance
```bash
# Clean old worktrees
find /var/clide/worktrees -type d -mtime +7 -exec rm -rf {} \;

# Vacuum HLS database
sqlite3 /home/clide/hook-line-sinker/hls_webhooks.db "VACUUM;"

# Archive old logs
tar -czf "/archive/clide-logs-$(date +%Y%W).tar.gz" /var/clide/logs/
```

### Monthly Maintenance
```bash
# Update dependencies
cd /home/clide/hook-line-sinker && npm update
cd /home/clide/clidehook && git pull

# Review and optimize queue performance
deck stats --period 30d

# Security updates
sudo apt update && sudo apt upgrade
```

## Support Information

### Log Locations
- HLS: `/var/clide/logs/hls/`
- DECK: `/var/clide/logs/deck/`
- CLIDEHOOK: `/var/clide/logs/clidehook/`
- Agent logs: `/var/clide/logs/clidehook/agents/`

### Configuration Files
- HLS: `/home/clide/hook-line-sinker/.env`
- DECK: `/var/clide/deck/config.yaml`
- CLIDEHOOK: `/var/clide/config/clidehook.conf`

### Getting Help
- GitHub Issues: https://github.com/clidecoder/clidehook/issues
- Documentation: https://github.com/clidecoder/clidehook/docs
- Community: Discord/Slack channel

Remember to always test configuration changes in a staging environment before applying to production!