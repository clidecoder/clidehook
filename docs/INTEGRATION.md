# CLIDE Integration Architecture: HLS → DECK → CLIDEHOOK

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Component Interactions](#component-interactions)
- [GitHub Events](#github-events)
- [Implementation Guide](#implementation-guide)
- [Configuration](#configuration)
- [Security Considerations](#security-considerations)
- [Monitoring & Debugging](#monitoring--debugging)
- [Deployment](#deployment)

## Overview

The CLIDE (CLI IDE) autonomous development system integrates with GitHub through a three-layer architecture that ensures reliable, scalable, and intelligent webhook processing:

1. **HLS (Hook Line Sinker)** - Webhook receiver and validator
2. **DECK (Development Execution Control Kernel)** - Queue management and concurrency control
3. **CLIDEHOOK** - CLIDE execution engine with sub-agent orchestration

This architecture separates concerns, allowing each component to excel at its specific role while maintaining system resilience.

## Architecture

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐      ┌──────────────┐
│   GitHub    │──────│     HLS     │──────│    DECK     │──────│  CLIDEHOOK   │
│  Webhooks   │      │  Receiver   │      │    Queue    │      │   Execute    │
└─────────────┘      └─────────────┘      └─────────────┘      └──────────────┘
      │                     │                     │                      │
      │                     │                     │                      │
   Events              Validate &              Manage               Autonomous
                        Filter               Concurrency           Development
```

### Component Responsibilities

#### HLS (Hook Line Sinker)
- Receives and validates GitHub webhooks
- Stores webhook events in SQLite database
- Filters CLIDE-relevant events
- Manages repository-specific prompt templates
- Dispatches events to DECK queue

#### DECK (Development Execution Control Kernel)
- Manages development session queue
- Controls concurrency limits
- Implements priority queuing
- Handles resource allocation
- Triggers CLIDEHOOK execution

#### CLIDEHOOK
- Creates isolated development environments (git worktrees)
- Manages tmux sessions for persistent context
- Orchestrates sub-agents (planning, implementation, documentation, testing)
- Handles GitHub API interactions
- Implements CLIDE communication protocol

## Component Interactions

### 1. Webhook Reception Flow

```javascript
// HLS webhook handler
app.post('/webhook/:repo', async (req, res) => {
    const payload = req.body;
    const signature = req.headers['x-hub-signature-256'];
    
    // Validate webhook signature
    if (!validateSignature(payload, signature)) {
        return res.status(401).send('Invalid signature');
    }
    
    // Store in database
    const eventId = await storeWebhookEvent(payload);
    
    // Check if CLIDE-relevant
    if (isClideEvent(payload)) {
        await dispatchToDeck(payload);
    }
    
    res.status(200).send('OK');
});
```

### 2. DECK Queue Dispatch

```javascript
async function dispatchToDeck(payload) {
    const repo = payload.repository.full_name;
    const issueNumber = payload.issue?.number || payload.pull_request?.number;
    const priority = calculatePriority(payload);
    
    const metadata = {
        event_type: payload.headers['x-github-event'],
        action: payload.action,
        timestamp: new Date().toISOString(),
        comment_body: payload.comment?.body,
        is_clide_comment: payload.comment?.body?.startsWith('CLIDE:')
    };
    
    // Queue to DECK
    exec(`deck queue ${repo} ${issueNumber} --priority ${priority} --metadata '${JSON.stringify(metadata)}'`);
}
```

### 3. CLIDEHOOK Execution

```bash
#!/bin/bash
# CLIDEHOOK main execution script

REPO=$1
ISSUE_NUMBER=$2
METADATA=$3

# Parse metadata
EVENT_TYPE=$(echo $METADATA | jq -r '.event_type')
ACTION=$(echo $METADATA | jq -r '.action')

# Create working environment
setup_environment() {
    WORKTREE_PATH="/var/clide/worktrees/${REPO//\//-}-issue-${ISSUE_NUMBER}"
    TMUX_SESSION="clide-${REPO//\//-}-${ISSUE_NUMBER}"
    
    # Create git worktree
    git worktree add "$WORKTREE_PATH" -b "clide/issue-${ISSUE_NUMBER}"
    
    # Start tmux session
    tmux new-session -d -s "$TMUX_SESSION" -c "$WORKTREE_PATH"
}

# Route to appropriate handler
case "${EVENT_TYPE}.${ACTION}" in
    "issues.opened")
        setup_environment
        execute_planning_agent
        ;;
    "issue_comment.created")
        if [[ $(echo $METADATA | jq -r '.is_clide_comment') == "false" ]]; then
            execute_response_handler
        fi
        ;;
    "pull_request_review.submitted")
        execute_review_handler
        ;;
esac
```

## GitHub Events

### Primary Events

| Event | Action | Purpose | CLIDE Response |
|-------|--------|---------|----------------|
| issues | opened | New issue created | Setup environment, analyze requirements |
| issues | closed | Issue closed | Cleanup worktree and tmux session |
| issues | reopened | Issue reopened | Restore or recreate environment |
| issue_comment | created | New comment | Parse for CLIDE instructions or questions |
| issue_comment | edited | Comment edited | Re-parse for updated instructions |

### Pull Request Events

| Event | Action | Purpose | CLIDE Response |
|-------|--------|---------|----------------|
| pull_request | opened | PR created | Link to issue, add description |
| pull_request | synchronize | New commits | Update PR description if needed |
| pull_request | closed | PR merged/closed | Cleanup and celebrate |
| pull_request_review | submitted | Review submitted | Read feedback, plan changes |
| pull_request_review_comment | created | Inline comment | Respond or implement changes |

### Control Events

| Event | Action | Purpose | CLIDE Response |
|-------|--------|---------|----------------|
| issues | labeled | Label added | Check for priority/control labels |
| issues | unlabeled | Label removed | Update status accordingly |
| issues | assigned | Assigned to CLIDE | Begin or resume work |
| issues | unassigned | Unassigned from CLIDE | Pause work |

## Implementation Guide

### Step 1: Configure HLS Integration

```javascript
// hls-config.js
module.exports = {
    repositories: {
        'org/repo': {
            clide_enabled: true,
            deck_endpoint: 'http://localhost:8090',
            priority_labels: {
                'urgent': 'high',
                'bug': 'medium',
                'enhancement': 'low'
            }
        }
    },
    clide_detection: {
        prefix: 'CLIDE:',
        bot_username: 'clide-bot',
        human_detection: /^(?!CLIDE:)/
    }
};
```

### Step 2: DECK Configuration

```yaml
# /var/clide/deck/config.yaml
max_concurrent: 3
default_priority: medium
ticket_timeout: 3600
cleanup_interval: 300

repositories:
  - pattern: "org/*"
    max_concurrent: 2
    executor: "/usr/local/bin/clidehook"
    
priorities:
  high: 
    weight: 100
    max_wait: 300
  medium:
    weight: 50
    max_wait: 900
  low:
    weight: 10
    max_wait: 3600
```

### Step 3: CLIDEHOOK Sub-Agents

```bash
# planning-agent.sh
execute_planning_agent() {
    local ISSUE_NUMBER=$1
    local WORKTREE_PATH=$2
    
    # Get issue details
    ISSUE_BODY=$(gh issue view $ISSUE_NUMBER --json body -q .body)
    
    # Read claude.md for project context
    CLAUDE_MD=$(cat $WORKTREE_PATH/claude.md 2>/dev/null || echo "")
    
    # Execute planning prompt
    PLAN=$(claude-code --prompt "planning" \
        --context "issue:$ISSUE_BODY" \
        --context "claude.md:$CLAUDE_MD" \
        --worktree "$WORKTREE_PATH")
    
    # Post plan as comment
    gh issue comment $ISSUE_NUMBER --body "CLIDE: Planning complete

$PLAN"
}
```

### Step 4: Communication Protocol

```javascript
// clide-communication.js
class ClideComm {
    constructor(repo, issueNumber) {
        this.repo = repo;
        this.issueNumber = issueNumber;
    }
    
    async postComment(message, context = 'issue') {
        const body = `CLIDE: ${message}`;
        
        if (context === 'issue') {
            await exec(`gh issue comment ${this.issueNumber} --body "${body}"`);
        } else if (context === 'pr') {
            await exec(`gh pr comment ${this.issueNumber} --body "${body}"`);
        }
    }
    
    async updateLabel(label, action = 'add') {
        const command = action === 'add' ? 'add' : 'remove';
        await exec(`gh issue edit ${this.issueNumber} --${command}-label "${label}"`);
    }
    
    async askClarification(question) {
        await this.postComment(`I need clarification: ${question}`);
        await this.updateLabel('awaiting-response', 'add');
        await this.updateLabel('working', 'remove');
    }
}
```

## Configuration

### Repository-Level Configuration (claude.md)

```markdown
# CLIDE Configuration

## Development Standards
- Language: TypeScript
- Framework: React with Vite
- Testing: Jest with React Testing Library
- Code Style: ESLint + Prettier

## CLIDE Behavior
- Always write tests for new features
- Update README.md with new functionality
- Use conventional commits
- Create focused, atomic commits

## Project Structure
- Components in src/components/
- Utilities in src/utils/
- Tests adjacent to source files

## Dependencies
- Prefer existing dependencies over adding new ones
- Document reasons for new dependencies in PR
```

### HLS Prompt Templates

```markdown
<!-- prompts/repos/org/repo/clide-planning.md -->
# Planning Agent Prompt

You are the CLIDE Planning Agent. Analyze the GitHub issue and create a detailed implementation plan.

## Issue Details
{{issue_body}}

## Project Context
{{claude_md}}

## Your Task
1. Identify the core requirements
2. List any ambiguities that need clarification
3. Create a step-by-step implementation plan
4. Identify which files need to be modified or created
5. Estimate complexity and potential risks

Respond with a structured plan that the Implementation Agent can follow.
```

## Security Considerations

### Webhook Validation
```javascript
function validateSignature(payload, signature) {
    const secret = process.env.GITHUB_WEBHOOK_SECRET;
    const hmac = crypto.createHmac('sha256', secret);
    const digest = 'sha256=' + hmac.update(JSON.stringify(payload)).digest('hex');
    return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(digest));
}
```

### Sandboxing
- Git worktrees provide isolated development spaces
- Tmux sessions run with limited permissions
- No access to production credentials
- All GitHub operations use token with minimal required scopes

### Rate Limiting
- DECK implements queue-based rate limiting
- Respect GitHub API rate limits
- Exponential backoff for retries

## Monitoring & Debugging

### Logging Architecture
```
/var/log/clide/
├── hls/
│   ├── webhook-events.log
│   └── errors.log
├── deck/
│   ├── queue-operations.log
│   └── execution.log
└── clidehook/
    ├── sessions/
    │   └── issue-{number}.log
    └── agents/
        ├── planning.log
        ├── implementation.log
        └── testing.log
```

### Health Checks
```bash
# Check HLS webhook receiver
curl http://localhost:8080/health

# Check DECK queue status
deck status

# Check CLIDEHOOK sessions
tmux ls | grep clide-

# Check worktrees
git worktree list | grep clide/
```

### Debugging Commands
```bash
# View DECK queue
deck list --all

# Inspect specific ticket
deck inspect org/repo 123

# View CLIDE session
tmux attach -t clide-org-repo-123

# Check agent logs
tail -f /var/log/clide/clidehook/agents/implementation.log
```

## Deployment

### Prerequisites
- GitHub App or webhook configuration
- Claude Code CLI configured
- Node.js 18+ for HLS
- Go 1.21+ for DECK (or use binary)
- tmux 3.0+
- git 2.30+ (worktree support)

### Installation Steps

1. **Deploy HLS**
```bash
git clone https://github.com/clidecoder/hook-line-sinker
cd hook-line-sinker
npm install
npm run setup-db
npm start
```

2. **Install DECK**
```bash
git clone https://github.com/clidecoder/deck
cd deck
go build -o deck cmd/deck/main.go
sudo mv deck /usr/local/bin/
deck init
```

3. **Setup CLIDEHOOK**
```bash
git clone https://github.com/clidecoder/clidehook
cd clidehook
./install.sh
```

4. **Configure GitHub Webhook**
- Add webhook URL: `https://your-domain/webhook/org/repo`
- Select events: Issues, Issue comments, Pull requests, Pull request reviews
- Set secret for validation

5. **Start Services**
```bash
# Start HLS
pm2 start hls.js --name hls

# Start DECK worker
deck worker start

# Enable CLIDE for repository
deck config set org/repo clide_enabled true
```

### Production Considerations
- Use systemd or pm2 for process management
- Configure log rotation
- Set up monitoring alerts
- Regular backup of DECK queue state
- Implement graceful shutdown handlers

## Troubleshooting

### Common Issues

**Issue: Webhooks not received**
- Check webhook configuration in GitHub
- Verify HLS is running and accessible
- Check firewall rules
- Validate webhook secret

**Issue: DECK not processing queue**
- Check `deck status`
- Verify worker is running
- Check for stuck tickets
- Review resource limits

**Issue: CLIDE not responding**
- Check tmux session exists
- Verify Claude Code CLI is authenticated
- Check agent logs for errors
- Ensure git worktree was created

**Issue: GitHub API rate limits**
- Implement caching in HLS
- Use conditional requests
- Spread operations over time
- Consider GitHub App for higher limits

### Recovery Procedures

```bash
# Clear stuck DECK ticket
deck clear org/repo 123 --force

# Cleanup orphaned worktree
git worktree remove /var/clide/worktrees/org-repo-issue-123

# Kill hung tmux session
tmux kill-session -t clide-org-repo-123

# Reset CLIDE for issue
./scripts/reset-issue.sh org/repo 123
```

## Best Practices

1. **Always prefix CLIDE messages** with "CLIDE:" for clear identification
2. **Use atomic operations** - each webhook should complete quickly
3. **Implement idempotency** - repeated webhooks should not cause issues
4. **Monitor resource usage** - prevent runaway processes
5. **Regular cleanup** - remove old worktrees and sessions
6. **Audit logging** - track all CLIDE actions for debugging
7. **Graceful degradation** - system should handle component failures

## Future Enhancements

- WebSocket support for real-time updates
- Multi-region deployment for reliability
- Advanced caching strategies
- Machine learning for better planning
- Integration with CI/CD pipelines
- Support for GitLab and Bitbucket