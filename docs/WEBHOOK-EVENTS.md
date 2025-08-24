# GitHub Webhook Events for CLIDE

## Complete Event Reference

This document provides a comprehensive reference of all GitHub webhook events that CLIDE processes, including payload structures, detection logic, and handling strategies.

## Event Categories

### 1. Issue Lifecycle Events

#### issues.opened
**Purpose**: Initialize CLIDE development environment for new issues

**Payload Structure**:
```json
{
  "action": "opened",
  "issue": {
    "number": 123,
    "title": "Add user authentication",
    "body": "We need to implement OAuth2...",
    "state": "open",
    "labels": [{"name": "enhancement"}, {"name": "urgent"}],
    "assignee": {"login": "clide-bot"},
    "created_at": "2024-01-15T10:00:00Z"
  },
  "repository": {
    "full_name": "org/repo",
    "default_branch": "main"
  },
  "sender": {"login": "human-developer"}
}
```

**CLIDE Actions**:
1. Create git worktree from default branch
2. Start tmux session
3. Read claude.md configuration
4. Execute planning agent
5. Post initial response with plan or clarifications
6. Add "working" label

#### issues.closed
**Purpose**: Cleanup resources when issue is resolved

**Detection**: `action == "closed"`

**CLIDE Actions**:
1. Stop any running processes
2. Remove git worktree
3. Kill tmux session
4. Post completion message if PR was merged
5. Archive logs

#### issues.reopened
**Purpose**: Resume work on previously closed issue

**CLIDE Actions**:
1. Check if previous work exists
2. Restore worktree or create new one
3. Post status update
4. Resume from last known state

### 2. Communication Events

#### issue_comment.created
**Purpose**: Process new instructions or respond to questions

**Human Comment Detection**:
```javascript
function isHumanComment(comment) {
    return !comment.body.startsWith('CLIDE:') && 
           comment.user.login !== 'clide-bot';
}
```

**CLIDE Response Matrix**:
| Comment Pattern | CLIDE Action |
|----------------|--------------|
| Question about implementation | Provide clarification |
| "HALT WORK" | Immediately stop all processing |
| Additional requirements | Update plan and continue |
| Approval phrases ("looks good", "proceed") | Continue to next phase |
| Code snippets | Incorporate into implementation |

#### issue_comment.edited
**Purpose**: Detect updated instructions

**CLIDE Actions**:
1. Compare with previous version
2. Identify what changed
3. Adjust plan if needed
4. Acknowledge changes

### 3. Pull Request Events

#### pull_request.opened
**Purpose**: Track PR created by CLIDE

**PR Description Template**:
```markdown
## Summary
This PR implements the requirements from #{{issue_number}}

## Changes Made
- {{list of key changes}}

## Testing
- {{test coverage added}}

## Notes
{{implementation decisions explained}}

---
*This PR was created by CLIDE autonomous development system*
```

#### pull_request.synchronize
**Purpose**: Handle new commits to CLIDE's PR

**CLIDE Actions**:
1. Update PR description if significant changes
2. Respond to any failed checks
3. Notify of push completion

#### pull_request_review.submitted
**Purpose**: Process code review feedback

**Review Response Logic**:
```javascript
switch(review.state) {
    case 'approved':
        postComment("CLIDE: Thank you for the approval! 🎉");
        updateLabel('ready-to-merge');
        break;
    case 'changes_requested':
        analyzeRequestedChanges();
        postComment("CLIDE: I'll address these changes");
        implementChanges();
        break;
    case 'commented':
        analyzeComments();
        respondToQuestions();
        break;
}
```

#### pull_request_review_comment.created
**Purpose**: Respond to inline code comments

**CLIDE Actions**:
1. Analyze comment context
2. Determine if change is needed
3. Either explain decision or implement change
4. Reply to thread when complete

### 4. Control Events

#### issues.labeled
**Purpose**: Respond to control labels

**Label Handlers**:
| Label | Action |
|-------|--------|
| `urgent` | Increase priority in DECK queue |
| `halt-work` | Stop all processing immediately |
| `needs-tests` | Trigger testing agent |
| `needs-docs` | Trigger documentation agent |
| `ready-for-clide` | Begin or resume work |

#### issues.assigned
**Purpose**: Track assignment to CLIDE bot

**CLIDE Actions**:
- If assigned to clide-bot: Begin work
- If assigned to human: Pause and wait
- If unassigned: Continue current state

### 5. Advanced Event Handling

#### Event Combinations
Some actions require checking multiple conditions:

```javascript
function shouldCLIDEWork(payload) {
    const issue = payload.issue;
    const isAssignedToCLIDE = issue.assignee?.login === 'clide-bot';
    const hasHaltLabel = issue.labels.some(l => l.name === 'halt-work');
    const isClosed = issue.state === 'closed';
    
    return isAssignedToCLIDE && !hasHaltLabel && !isClosed;
}
```

#### Event Debouncing
Rapid event sequences are handled intelligently:

```javascript
class EventDebouncer {
    constructor(delay = 5000) {
        this.pending = new Map();
        this.delay = delay;
    }
    
    debounce(eventKey, handler) {
        if (this.pending.has(eventKey)) {
            clearTimeout(this.pending.get(eventKey));
        }
        
        const timeout = setTimeout(() => {
            handler();
            this.pending.delete(eventKey);
        }, this.delay);
        
        this.pending.set(eventKey, timeout);
    }
}
```

## Event Priority System

Events are prioritized for processing:

1. **Critical** (Process immediately)
   - `HALT WORK` commands
   - Security-related labels
   - Admin interventions

2. **High** (Process within 1 minute)
   - issues.opened with "urgent" label
   - pull_request_review with changes_requested
   - Direct questions to CLIDE

3. **Normal** (Process within 5 minutes)
   - Regular issue comments
   - PR synchronization
   - Label changes

4. **Low** (Process when available)
   - Comment edits
   - Assignment changes
   - Non-critical labels

## Webhook Payload Validation

### Required Fields Validation
```javascript
function validateIssueEvent(payload) {
    const required = ['action', 'issue', 'repository', 'sender'];
    const missing = required.filter(field => !payload[field]);
    
    if (missing.length > 0) {
        throw new Error(`Missing required fields: ${missing.join(', ')}`);
    }
    
    if (!payload.issue.number || !payload.repository.full_name) {
        throw new Error('Invalid issue or repository data');
    }
}
```

### Signature Verification
```javascript
function verifyWebhookSignature(payload, signature, secret) {
    const expectedSignature = `sha256=${crypto
        .createHmac('sha256', secret)
        .update(JSON.stringify(payload))
        .digest('hex')}`;
    
    return crypto.timingSafeEqual(
        Buffer.from(signature),
        Buffer.from(expectedSignature)
    );
}
```

## Event Routing Decision Tree

```
Event Received
    │
    ├─ Validate Signature
    │   └─ Invalid → Reject (401)
    │
    ├─ Check Event Type
    │   └─ Not CLIDE-relevant → Store & Skip
    │
    ├─ Extract Metadata
    │   ├─ Repository
    │   ├─ Issue/PR Number
    │   └─ Priority Indicators
    │
    ├─ Check CLIDE Eligibility
    │   ├─ Is CLIDE enabled for repo?
    │   ├─ Is issue assigned to CLIDE?
    │   └─ Any blocking labels?
    │
    └─ Queue to DECK
        ├─ Set Priority
        ├─ Add Metadata
        └─ Return Success
```

## Special Event Sequences

### Issue Creation → PR Merge Flow
1. `issues.opened` → Setup environment
2. `issue_comment.created` → Clarifications
3. `issues.labeled` → Begin implementation
4. `pull_request.opened` → Link to issue
5. `pull_request_review.submitted` → Address feedback
6. `pull_request.merged` → Cleanup
7. `issues.closed` → Final cleanup

### Review Feedback Loop
1. `pull_request_review.submitted` → Analyze feedback
2. `pull_request_review_comment.created` → Specific changes
3. `push` → Update PR
4. `pull_request.synchronize` → Notify completion
5. Repeat until approved

## Error Scenarios

### Missing Required Data
```javascript
// Graceful handling of incomplete payloads
function extractIssueNumber(payload) {
    return payload.issue?.number || 
           payload.pull_request?.number || 
           payload.number ||
           null;
}
```

### Race Conditions
```javascript
// Prevent duplicate processing
const processedEvents = new Set();

function processEvent(eventId, handler) {
    if (processedEvents.has(eventId)) {
        return { status: 'duplicate', message: 'Event already processed' };
    }
    
    processedEvents.add(eventId);
    setTimeout(() => processedEvents.delete(eventId), 300000); // 5 min TTL
    
    return handler();
}
```

## Monitoring & Metrics

### Event Statistics to Track
- Total events received per repository
- Event type distribution
- Processing time per event type
- Error rate by event type
- CLIDE response time

### Health Indicators
```javascript
const metrics = {
    eventsReceived: 0,
    eventsProcessed: 0,
    eventsErrored: 0,
    averageProcessingTime: 0,
    queueDepth: 0,
    
    recordEvent(type, duration, success) {
        this.eventsReceived++;
        if (success) {
            this.eventsProcessed++;
            this.updateAverageTime(duration);
        } else {
            this.eventsErrored++;
        }
    }
};
```

## Testing Webhook Integration

### Manual Testing
```bash
# Test issue opened event
curl -X POST http://localhost:8080/webhook/org/repo \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: issues" \
  -H "X-Hub-Signature-256: sha256=..." \
  -d @test-payloads/issue-opened.json

# Test comment event
curl -X POST http://localhost:8080/webhook/org/repo \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: issue_comment" \
  -H "X-Hub-Signature-256: sha256=..." \
  -d @test-payloads/comment-created.json
```

### Automated Testing
```javascript
describe('Webhook Event Processing', () => {
    test('processes issue.opened event', async () => {
        const payload = loadFixture('issue-opened.json');
        const response = await processWebhook(payload);
        
        expect(response.queued).toBe(true);
        expect(response.priority).toBe('normal');
    });
    
    test('detects human comments correctly', () => {
        const clideComment = { body: 'CLIDE: Processing...', user: { login: 'clide-bot' } };
        const humanComment = { body: 'Please add tests', user: { login: 'developer' } };
        
        expect(isHumanComment(clideComment)).toBe(false);
        expect(isHumanComment(humanComment)).toBe(true);
    });
});
```

## Security Considerations

### Event Validation Checklist
- [ ] Verify webhook signature
- [ ] Validate sender permissions
- [ ] Check repository allowlist
- [ ] Sanitize comment content
- [ ] Validate issue/PR state
- [ ] Rate limit by repository
- [ ] Log all events for audit

### Preventing Abuse
```javascript
const rateLimiter = {
    attempts: new Map(),
    
    check(repo, limit = 100, window = 3600000) {
        const key = `${repo}:${Math.floor(Date.now() / window)}`;
        const current = this.attempts.get(key) || 0;
        
        if (current >= limit) {
            throw new Error('Rate limit exceeded');
        }
        
        this.attempts.set(key, current + 1);
    }
};
```