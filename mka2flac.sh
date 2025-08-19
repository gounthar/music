#!/usr/bin/env bash
# mka-to-flac.sh  —  Lossless batch converter

shopt -s nullglob                # No matches → empty array, avoids literal *.mka
for f in "$@"; do                # Accepts file list or glob, e.g. *.mka
  base="${f%.*}"
  codec=$(ffprobe -v error -select_streams a:0 \
          -show_entries stream=codec_name -of default=nw=1:nk=1 "$f")

  if [[ $codec == "flac" ]]; then
    echo "Copying FLAC stream → $base.flac"
    yes | ffmpeg -loglevel error -i "$f" -map 0:a -c copy -map_metadata 0 "$base.flac"
  else
    echo "Transcoding $codec → FLAC → $base.flac"
    yes | ffmpeg -loglevel error -i "$f" -c:a flac -compression_level 5 \
           -map_metadata 0 "$base.flac"
  fi
done

