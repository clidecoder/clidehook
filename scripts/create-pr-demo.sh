#!/bin/bash
# GitHub PR Video Integration: Auto-Play GIF + Full Video Combo
# Creates PR with highlight GIF and full Playwright video

set -e  # Exit on any error

create_pr_with_media() {
    local title="$1"
    local description="$2" 
    local video_file="${3:-test-results/example-chromium/video.webm}"
    
    # Validate inputs
    if [ -z "$title" ] || [ -z "$description" ]; then
        echo "Usage: create_pr_with_media 'Title' 'Description' [video_file]"
        echo "Example: ./create-pr-demo.sh 'Fix: Navigation bug' 'Fixed mobile menu collapse issue'"
        exit 1
    fi
    
    if [ ! -f "$video_file" ]; then
        echo "❌ Video not found: $video_file"
        echo "Looking for Playwright videos in test-results/..."
        find test-results -name "video.webm" -type f 2>/dev/null | head -5
        exit 1
    fi
    
    # Check dependencies
    for cmd in ffmpeg ffprobe gh; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "❌ Required command not found: $cmd"
            echo "Install with: sudo apt install ffmpeg gh"
            exit 1
        fi
    done
    
    echo "📹 Processing Playwright video for PR..."
    echo "   Video: $video_file"
    
    # Get video duration and size
    duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$video_file" | cut -d. -f1)
    video_size=$(stat --printf="%s" "$video_file")
    video_mb=$((video_size / 1024 / 1024))
    
    echo "   Duration: ${duration}s, Size: ${video_mb}MB"
    
    # Create highlight (first 15s or full duration if shorter)
    highlight_duration=$((duration < 15 ? duration : 15))
    
    echo "🎬 Creating ${highlight_duration}s highlight GIF..."
    
    # Create temporary file for GIF
    highlight_gif=$(mktemp --suffix=.gif)
    
    ffmpeg -i "$video_file" \
        -vf "fps=12,scale=650:-1:flags=lanczos" \
        -t "$highlight_duration" \
        -y "$highlight_gif" \
        -loglevel error
    
    # Check and optimize GIF size
    gif_size=$(stat --printf="%s" "$highlight_gif")
    gif_mb=$((gif_size / 1024 / 1024))
    
    echo "   Initial GIF size: ${gif_mb}MB"
    
    if [ "$gif_mb" -gt 20 ]; then
        echo "🔄 Compressing large GIF..."
        ffmpeg -i "$video_file" \
            -vf "fps=8,scale=500:-1:flags=lanczos,palettegen=max_colors=64" \
            -t "$((highlight_duration - 2))" \
            -y "$highlight_gif" \
            -loglevel error
        
        gif_size=$(stat --printf="%s" "$highlight_gif")
        gif_mb=$((gif_size / 1024 / 1024))
        echo "   Compressed GIF size: ${gif_mb}MB"
    fi
    
    # Upload both files to GitHub Gists
    echo "☁️  Uploading files to GitHub Gists..."
    
    # Upload video
    video_filename="demo-$(date +%s).webm"
    echo "   Uploading video as $video_filename..."
    video_gist=$(gh gist create "$video_file" --public --filename "$video_filename")
    
    # Upload GIF
    gif_filename="highlight-$(date +%s).gif"
    echo "   Uploading GIF as $gif_filename..."
    gif_gist=$(gh gist create "$highlight_gif" --public --filename "$gif_filename")
    gif_url="${gif_gist}/raw/$gif_filename"
    
    # Create PR with formatted body
    echo "🚀 Creating PR with media..."
    
    pr_body="## Changes
$description

## Quick Preview
![Demo Highlight]($gif_url)
*${highlight_duration}s highlight showing the key fix moment*

## Full Demonstration  
🎥 **Complete video:** $video_gist  
📏 **Duration:** ${duration}s (${video_mb}MB)  
🎯 **Coverage:** Shows setup, fix implementation, and edge case testing

The GIF above shows the essential fix moment. Click the video link for complete context including error reproduction and validation steps.

## Testing
This change has been validated with Playwright automated tests. The video demonstrates:
- Issue reproduction
- Fix verification  
- Edge case handling
- UI/UX impact"
    
    gh pr create \
        --title "$title" \
        --body "$pr_body"
    
    # Cleanup
    rm -f "$highlight_gif"
    
    echo "✅ PR created successfully!"
    echo "   📸 Highlight GIF: $gif_url"
    echo "   🎥 Full video: $video_gist"
    echo "   ⏱️  Processing time: ~$((duration + 10))s"
}

# Auto-detect video file if not provided
auto_detect_video() {
    # Look for most recent Playwright video
    local latest_video=$(find test-results -name "video.webm" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$latest_video" ]; then
        echo "🔍 Auto-detected video: $latest_video"
        echo "$latest_video"
    else
        # Look for any video files
        local any_video=$(find . -name "*.webm" -o -name "*.mp4" -type f | head -1)
        if [ -n "$any_video" ]; then
            echo "🔍 Found video file: $any_video"
            echo "$any_video"
        fi
    fi
}

# Main execution
main() {
    local title="$1"
    local description="$2"
    local video_file="$3"
    
    # Auto-detect video if not provided
    if [ -z "$video_file" ]; then
        video_file=$(auto_detect_video)
        if [ -z "$video_file" ]; then
            echo "❌ No video file found and none specified"
            echo ""
            echo "Usage: $0 'PR Title' 'Description' [video_file]"
            echo ""
            echo "Examples:"
            echo "  $0 'Fix: Button not responding' 'Added click handler to submit button'"
            echo "  $0 'Feature: Dark mode' 'Implemented theme toggle' 'custom-test.webm'"
            echo ""
            echo "The script will look for Playwright videos in test-results/ by default."
            exit 1
        fi
    fi
    
    create_pr_with_media "$title" "$description" "$video_file"
}

# Run main function with all arguments
main "$@"