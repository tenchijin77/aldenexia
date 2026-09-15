#!/bin/sh
printf '\033c\033]0;%s\a' Aldenexia-Lightfall
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Aldenexia_Lightfall.x86_64" "$@"
