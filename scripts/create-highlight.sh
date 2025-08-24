#!/bin/bash
# Extract specific time segment for highlight GIF creation
# Usage: ./create-highlight.sh video.webm "00:00:08" "10"

set -e

VIDEO_FILE="$1"
START_TIME="$2"  # e.g., "00:00:05" 
DURATION="$3"    # e.g., "12"
OUTPUT_FILE="${4:-highlight.gif}"

# Validate inputs
if [ $# -lt 3 ]; then
    echo "Usage: $0 <video_file> <start_time> <duration> [output_file]"
    echo ""
    echo "Examples:"
    echo "  $0 test.webm '00:00:05' '10'              # 10s from 5s mark"
    echo "  $0 test.webm '00:00:08' '15' custom.gif   # 15s from 8s mark"
    echo "  $0 test.webv '0:30' '8'                   # 8s from 30s mark"
    echo ""
    echo "Time formats supported:"
    echo "  - HH:MM:SS (00:01:30)"
    echo "  - MM:SS (01:30)"
    echo "  - SS (90)"
    echo "  - M:SS (1:30)"
    exit 1
fi

if [ ! -f "$VIDEO_FILE" ]; then
    echo "❌ Video file not found: $VIDEO_FILE"
    exit 1
fi

# Check dependencies
for cmd in ffmpeg ffprobe; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ Required command not found: $cmd"
        echo "Install with: sudo apt install ffmpeg"
        exit 1
    fi
done

echo "🎬 Creating highlight GIF..."
echo "   Video: $VIDEO_FILE"
echo "   Start: $START_TIME"
echo "   Duration: ${DURATION}s"
echo "   Output: $OUTPUT_FILE"

# Get video info
total_duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$VIDEO_FILE" | cut -d. -f1)
echo "   Video duration: ${total_duration}s"

# Validate start time and duration
if ! ffprobe -v quiet -ss "$START_TIME" -t 1 -f null - -i "$VIDEO_FILE" 2>/dev/null; then
    echo "❌ Invalid start time: $START_TIME"
    exit 1
fi

# Create the highlight GIF with smart quality based on duration
if [ "$DURATION" -le 8 ]; then
    # Short clips: high quality
    QUALITY_SETTINGS="fps=15,scale=700:-1:flags=lanczos"
    echo "   Quality: High (short clip)"
elif [ "$DURATION" -le 15 ]; then
    # Medium clips: balanced
    QUALITY_SETTINGS="fps=12,scale=650:-1:flags=lanczos"
    echo "   Quality: Medium (balanced)"
else
    # Long clips: compressed
    QUALITY_SETTINGS="fps=8,scale=500:-1:flags=lanczos,palettegen=max_colors=128"
    echo "   Quality: Compressed (long clip)"
fi

# Extract the segment
ffmpeg -i "$VIDEO_FILE" \
    -ss "$START_TIME" \
    -t "$DURATION" \
    -vf "$QUALITY_SETTINGS" \
    -y "$OUTPUT_FILE" \
    -loglevel error

# Check output
if [ -f "$OUTPUT_FILE" ]; then
    gif_size=$(stat --printf="%s" "$OUTPUT_FILE")
    gif_mb=$((gif_size / 1024 / 1024))
    
    echo "✅ Highlight created successfully!"
    echo "   Size: ${gif_mb}MB"
    echo "   File: $OUTPUT_FILE"
    
    # Warn if too large for GitHub
    if [ "$gif_mb" -gt 20 ]; then
        echo "⚠️  Warning: GIF is ${gif_mb}MB, may be too large for GitHub (25MB limit)"
        echo "   Consider reducing duration or using lower quality settings"
    fi
else
    echo "❌ Failed to create GIF"
    exit 1
fi