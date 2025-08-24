# GitHub PR Video Integration: Auto-Play GIF + Full Video Combo

## Recommended Approach: Dual Media Strategy

For GitHub PRs, the optimal approach combines:
1. **Auto-play highlight GIF** - Immediate visual impact, shows key moments
2. **Full Gist video** - Complete demonstration with all details

This gives reviewers a quick preview while providing full context for thorough review.

## GitHub Constraints

- **Direct upload limit**: 25MB
- **Gist limit**: 100MB per file
- **Typical Playwright video**: 2-10MB for 30-60 seconds
- **GIF size**: ~1-2MB per second at decent quality

## Implementation Script

```bash
#!/bin/bash
# Dual upload: Highlight GIF + Full video

VIDEO_FILE="test-results/example-chromium/video.webm"
HIGHLIGHT_GIF="highlight.gif"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "❌ Video file not found: $VIDEO_FILE"
    exit 1
fi

echo "📹 Processing Playwright video for PR..."

# 1. Create highlight GIF (first 15 seconds, optimized)
echo "🎬 Creating highlight GIF..."
ffmpeg -i "$VIDEO_FILE" \
    -vf "fps=12,scale=700:-1:flags=lanczos" \
    -t 15 \
    -y "$HIGHLIGHT_GIF"

# Check GIF size
GIF_SIZE=$(du -m "$HIGHLIGHT_GIF" | cut -f1)
if [ "$GIF_SIZE" -gt 24 ]; then
    echo "⚠️  GIF too large (${GIF_SIZE}MB), creating compressed version..."
    ffmpeg -i "$VIDEO_FILE" \
        -vf "fps=8,scale=500:-1:flags=lanczos,palettegen=max_colors=128" \
        -t 12 \
        -y "$HIGHLIGHT_GIF"
fi

# 2. Upload full video to Gist
echo "☁️  Uploading full video to Gist..."
GIST_URL=$(gh gist create "$VIDEO_FILE" --public --filename "demo-$(date +%s).webm")

# 3. Upload GIF to Gist for embedding
echo "🖼️  Uploading highlight GIF..."
GIF_GIST=$(gh gist create "$HIGHLIGHT_GIF" --public --filename "highlight.gif")
GIF_RAW_URL="${GIF_GIST}/raw/highlight.gif"

# 4. Create PR with both media
echo "🚀 Creating PR..."
gh pr create \
    --title "$1" \
    --body "## Changes
$2

## Quick Preview
![Demo Highlight]($GIF_RAW_URL)

## Full Demonstration  
🎥 **Complete video:** $GIST_URL  
📏 **Duration:** $(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$VIDEO_FILE" | cut -d. -f1)s

The GIF shows the key fix moment. Watch the full video for complete context including setup and edge cases."

# 5. Cleanup
rm "$HIGHLIGHT_GIF"

echo "✅ PR created with highlight GIF + full video"
echo "   GIF: $GIF_RAW_URL"  
echo "   Video: $GIST_URL"
```

## GIF Optimization Guidelines

### Highlight GIF Strategy
Focus on the **key 10-15 seconds** that show:
- The bug occurring
- The fix being applied  
- The result working

### Quality Settings by Content

#### Simple UI Changes (buttons, forms)
```bash
# High quality for clear UI elements
ffmpeg -i "$VIDEO_FILE" \
    -vf "fps=15,scale=700:-1:flags=lanczos" \
    -t 15 highlight.gif
```
**Result**: ~15-20MB, crystal clear UI

#### Complex Animations/Scrolling
```bash
# Balanced for motion
ffmpeg -i "$VIDEO_FILE" \
    -vf "fps=10,scale=600:-1:flags=lanczos" \
    -t 12 highlight.gif  
```
**Result**: ~10-15MB, smooth motion

#### Dense/Busy Interfaces  
```bash
# Compressed for readability
ffmpeg -i "$VIDEO_FILE" \
    -vf "fps=8,scale=500:-1:flags=lanczos,palettegen=max_colors=128" \
    -t 10 highlight.gif
```
**Result**: ~8-12MB, still readable

### Smart Duration Selection

Instead of just taking the first 15 seconds, extract the key moment:

```bash
#!/bin/bash
# Extract specific time segment for highlight

VIDEO_FILE="$1"
START_TIME="$2"  # e.g., "00:00:05" 
DURATION="$3"    # e.g., "12"

ffmpeg -i "$VIDEO_FILE" \
    -ss "$START_TIME" \
    -t "$DURATION" \
    -vf "fps=12,scale=650:-1:flags=lanczos" \
    highlight.gif
```

Usage: `./create_highlight.sh video.webm "00:00:08" "10"`

## PR Template Integration

### Markdown Structure
```markdown
## Issue
Brief description of what was broken

## Solution  
What changed in the code

## Demo

### Quick Preview
![Bug Fix Highlight](https://gist.github.com/.../raw/highlight.gif)
*Key moment showing the fix in action*

### Complete Demonstration
🎥 **Full video:** https://gist.github.com/.../demo-video.webm
📊 **Test coverage:** Shows edge cases and different scenarios  
⏱️ **Duration:** 45 seconds

## Testing
How to reproduce and verify locally
```

## Advanced Script with Error Handling

```bash
#!/bin/bash
set -e  # Exit on any error

create_pr_with_media() {
    local title="$1"
    local description="$2" 
    local video_file="${3:-test-results/example-chromium/video.webm}"
    
    # Validate inputs
    if [ -z "$title" ] || [ -z "$description" ]; then
        echo "Usage: create_pr_with_media 'Title' 'Description' [video_file]"
        exit 1
    fi
    
    if [ ! -f "$video_file" ]; then
        echo "❌ Video not found: $video_file"
        exit 1
    fi
    
    # Get video duration
    duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$video_file" | cut -d. -f1)
    
    # Create highlight (first 15s or full duration if shorter)
    highlight_duration=$((duration < 15 ? duration : 15))
    
    echo "📹 Creating ${highlight_duration}s highlight from ${duration}s video..."
    
    ffmpeg -i "$video_file" \
        -vf "fps=12,scale=650:-1:flags=lanczos" \
        -t "$highlight_duration" \
        -y "highlight.gif" \
        -loglevel error
    
    # Check and optimize GIF size
    gif_size=$(stat --printf="%s" "highlight.gif")
    gif_mb=$((gif_size / 1024 / 1024))
    
    if [ "$gif_mb" -gt 20 ]; then
        echo "🔄 Compressing large GIF (${gif_mb}MB)..."
        ffmpeg -i "$video_file" \
            -vf "fps=8,scale=500:-1:flags=lanczos,palettegen=max_colors=64" \
            -t "$((highlight_duration - 2))" \
            -y "highlight.gif" \
            -loglevel error
    fi
    
    # Upload both files
    echo "☁️  Uploading files..."
    video_gist=$(gh gist create "$video_file" --public --filename "demo-$(date +%s).webm")
    gif_gist=$(gh gist create "highlight.gif" --public --filename "highlight.gif")
    gif_url="${gif_gist}/raw/highlight.gif"
    
    # Create PR
    gh pr create \
        --title "$title" \
        --body "## Changes
$description

## Quick Preview  
![Demo]($gif_url)

## Full Demo
🎥 **Complete video:** $video_gist  
⏱️ **Duration:** ${duration}s  

GIF shows the key fix moment. Full video includes setup and edge case testing."
    
    # Cleanup
    rm -f "highlight.gif"
    
    echo "✅ Success!"
    echo "   Highlight: $gif_url"
    echo "   Full video: $video_gist"
}

# Usage examples:
# create_pr_with_media "Fix: Navigation bug" "Fixed mobile menu collapse issue"
# create_pr_with_media "Feature: Dark mode" "Added theme toggle" "custom-video.webm"
```

## Claude Code Integration

For seamless Claude Code automation, save as `scripts/create-pr-demo.sh`:

```bash
#!/bin/bash
# Call from your main automation script

LATEST_VIDEO=$(find test-results -name "video.webm" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)

if [ -n "$LATEST_VIDEO" ]; then
    ./scripts/create-pr-demo.sh \
        "Fix: $ISSUE_TITLE" \
        "$COMMIT_MESSAGE" \
        "$LATEST_VIDEO"
else
    echo "⚠️  No Playwright video found, creating PR without demo"
    gh pr create --title "Fix: $ISSUE_TITLE" --body "$COMMIT_MESSAGE"
fi
```

## Benefits of This Approach

✅ **Immediate impact**: Reviewers see the fix instantly  
✅ **Complete context**: Full video available for deep review  
✅ **Fast loading**: Small GIF loads quickly in GitHub  
✅ **Reliable**: Both assets hosted on GitHub infrastructure  
✅ **Automated**: One script handles everything  
✅ **Mobile friendly**: GIFs work well on mobile GitHub  

This dual approach maximizes reviewer engagement while providing comprehensive demonstration of your Playwright-validated fixes.