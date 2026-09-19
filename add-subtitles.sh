#!/usr/bin/env bash
#
# add-subtitles.sh — download an HLS subtitle track, clean it up and mux it
# into an already downloaded (subtitle-less) video file.
#
# Usage: add-subtitles.sh <subtitle-url> <video-file>
#
#   <subtitle-url>  URI of the #EXT-X-MEDIA subtitle entry of the HLS playlist
#   <video-file>    Matroska file without subtitles; it is replaced by the
#                   same file with the subtitle track muxed in
#
set -euo pipefail

die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

if [[ $# -ne 2 ]]; then
	echo "Usage: $0 <subtitle-url> <video-file>" >&2
	echo "  Downloads the subtitle track, strips the leaked WebVTT headers," >&2
	echo "  and muxes it into <video-file>, replacing it in place." >&2
	exit 1
fi

subtitleUrl=$1
videoFile=$2

if [[ ! -f "$videoFile" ]]; then
	echo "Error: video file '$videoFile' not found." >&2
	exit 1
fi

case $videoFile in
	*.mkv) ;;
	*) die "video file must be a Matroska (.mkv) file: $videoFile" ;;
esac

command -v ffmpeg >/dev/null || die "ffmpeg not found in PATH"

# Small subtitle intermediates live here and are removed on exit.
tempdir=$(mktemp -d)
# Merged full-size file goes next to the target (same filesystem => atomic mv).
merged=$(mktemp "$(dirname "$videoFile")/.mux.XXXXXX.mkv")
trap 'rm -rf "$tempdir"' EXIT

rawSrt="$tempdir/raw.srt"
cleanSrt="$tempdir/clean.srt"
fixedSrt="$tempdir/fixed.srt"

ff() { ffmpeg -nostdin -loglevel warning -y "$@"; }


# 1. Download the subtitle track as SubRip.
ff -i "$subtitleUrl" "$rawSrt"
[ -s "$rawSrt" ] || die "no subtitles downloaded from $subtitleUrl"

# 2. Drop the WEBVTT/X-TIMESTAMP-MAP headers that leak in from each segment.
awk 'BEGIN{RS="";ORS="\n\n"} $0 !~ /WEBVTT|X-TIMESTAMP-MAP/' \
	"$rawSrt" > "$cleanSrt"
[ -s "$cleanSrt" ] || die "nothing left after stripping WEBVTT headers"

# 3. Let ffmpeg renumber the now non-consecutive subtitle entries.
ff -i "$cleanSrt" "$fixedSrt"

# 4. Mux the subtitles into the video and replace the original file.
ff -i "$videoFile" -i "$fixedSrt" -map 0 -map 1 -c copy "$merged"

# 5. Replace the original with the subtitles version
mv -- "$merged" "$videoFile"

printf 'Done: subtitles added to %s\n' "$videoFile"
