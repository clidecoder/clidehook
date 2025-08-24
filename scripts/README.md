# CLIDEHOOK Scripts

This directory contains utility scripts for the CLIDE autonomous development system.

## Scripts Overview

### 1. `create-pr-demo.sh`
**Purpose**: Create GitHub PRs with Playwright video demonstrations

**Features**:
- Automatically converts Playwright videos to highlight GIFs
- Uploads full video and GIF to GitHub Gists
- Creates PR with both embedded GIF and video link
- Smart GIF optimization based on content and size
- Auto-detection of latest Playwright videos

**Usage**:
```bash
# Basic usage with auto-detected video
./create-pr-demo.sh "Fix: Button not responding" "Added click handler to submit button"

# With specific video file
./create-pr-demo.sh "Feature: Dark mode" "Implemented theme toggle" "path/to/video.webm"

# Auto-detect from test-results/
./create-pr-demo.sh "Fix: Navigation bug" "Fixed mobile menu collapse"
```

**Requirements**:
- `ffmpeg` and `ffprobe` for video processing
- `gh` CLI for GitHub integration
- Playwright videos in `test-results/` directory

### 2. `create-highlight.sh`
**Purpose**: Extract specific time segments from videos as optimized GIFs

**Features**:
- Extract any time range from video
- Smart quality settings based on duration
- Multiple time format support
- Size optimization for GitHub limits

**Usage**:
```bash
# Extract 10 seconds starting at 5 second mark
./create-highlight.sh test.webm "00:00:05" "10"

# Extract 15 seconds from 8 second mark to custom file
./create-highlight.sh test.webm "00:00:08" "15" "bug-fix.gif"

# Extract from 30 second mark
./create-highlight.sh test.webm "0:30" "8"
```

**Time Formats**:
- `HH:MM:SS` - Hours:Minutes:Seconds (00:01:30)
- `MM:SS` - Minutes:Seconds (01:30)
- `SS` - Seconds (90)
- `M:SS` - Minutes:Seconds (1:30)

## Integration Examples

### With CLIDE Workflow

```bash
#!/bin/bash
# In your main CLIDE script

# Run tests
npm test

# Find latest Playwright video
LATEST_VIDEO=$(find test-results -name "video.webm" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)

if [ -n "$LATEST_VIDEO" ]; then
    # Create PR with video demo
    ./scripts/create-pr-demo.sh \
        "Fix: $ISSUE_TITLE" \
        "$COMMIT_MESSAGE" \
        "$LATEST_VIDEO"
else
    echo "⚠️  No video found, creating PR without demo"
    gh pr create --title "Fix: $ISSUE_TITLE" --body "$COMMIT_MESSAGE"
fi
```

### Custom Highlight Creation

```bash
#!/bin/bash
# Create multiple highlights from same video

VIDEO="test-results/demo.webm"

# Bug reproduction (first 10 seconds)
./scripts/create-highlight.sh "$VIDEO" "00:00:00" "10" "bug-repro.gif"

# Fix demonstration (middle section)
./scripts/create-highlight.sh "$VIDEO" "00:00:15" "12" "fix-demo.gif"

# Validation (last part)
./scripts/create-highlight.sh "$VIDEO" "00:00:30" "8" "validation.gif"
```

## Configuration

### Quality Settings

The scripts automatically choose quality settings based on content:

| Duration | FPS | Scale | Palette | Use Case |
|----------|-----|-------|---------|----------|
| ≤8s | 15 | 700px | Full | Short UI demos |
| 9-15s | 12 | 650px | Full | Balanced quality |
| >15s | 8 | 500px | 128 colors | Long sequences |

### Size Optimization

- **Target**: <20MB for reliable GitHub loading
- **Limit**: 25MB GitHub upload maximum
- **Auto-compression**: Triggered when initial GIF >20MB
- **Fallback**: Reduces duration by 2s and lowers quality

## Dependencies

### Required Tools

```bash
# Install on Ubuntu/Debian
sudo apt update
sudo apt install ffmpeg

# Install GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
sudo apt update
sudo apt install gh

# Authenticate with GitHub
gh auth login
```

### Optional Enhancements

```bash
# For better GIF optimization
sudo apt install gifsicle

# For video analysis
sudo apt install mediainfo
```

## Error Handling

### Common Issues

**"Video file not found"**
- Check path to video file
- Ensure Playwright is configured to record videos
- Verify test-results directory exists

**"Required command not found"**
- Install missing dependencies (ffmpeg, gh)
- Check PATH includes installed tools

**"GIF too large"**
- Reduce duration with create-highlight.sh
- Use lower quality settings
- Consider splitting into multiple shorter GIFs

**"GitHub authentication failed"**
- Run `gh auth login` to authenticate
- Ensure GitHub token has gist creation permissions

### Debug Mode

Enable verbose output:
```bash
export DEBUG=1
./create-pr-demo.sh "Test" "Debug run"
```

This will show:
- FFmpeg commands being executed
- File sizes at each step
- GitHub API responses
- Temporary file locations

## Best Practices

### Video Quality
- Record at reasonable resolution (1280x720 recommended)
- Keep test videos under 60 seconds when possible
- Focus on key interaction points
- Use consistent browser window sizes

### GIF Optimization
- Extract only the essential moments
- Use create-highlight.sh for precise timing
- Test GIF quality before PR creation
- Consider multiple short GIFs vs one long one

### PR Integration
- Include descriptive titles and descriptions
- Link GIFs to full videos for complete context
- Add testing instructions
- Tag relevant reviewers

## Advanced Usage

### Batch Processing

```bash
#!/bin/bash
# Process multiple test videos

for video in test-results/*/video.webm; do
    test_name=$(basename $(dirname "$video"))
    ./scripts/create-pr-demo.sh \
        "Fix: $test_name" \
        "Automated fix for $test_name test case" \
        "$video"
done
```

### Custom Templates

Create custom PR templates by modifying the `pr_body` variable in `create-pr-demo.sh`:

```bash
pr_body="## 🐛 Bug Fix: $title

### Problem
$description

### Solution
[Describe the technical solution]

### Demo
![Quick Preview]($gif_url)

### Full Test Video
🎥 $video_gist (${duration}s)

### Testing Checklist
- [ ] Bug reproduction confirmed
- [ ] Fix implementation validated  
- [ ] Edge cases tested
- [ ] No regressions introduced"
```

This comprehensive script collection enables seamless integration of Playwright video demonstrations into your GitHub PR workflow, making code reviews more engaging and informative.