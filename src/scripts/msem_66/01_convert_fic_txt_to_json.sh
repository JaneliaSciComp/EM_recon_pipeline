#!/bin/bash

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [-p PREFIX] INPUT.txt

Options:
  -p, --prefix   Path prefix to add before each relative image path
                 (default: "scan_000303")
  -h, --help     Show this help

Notes:
  - Output is written to INPUT.txt.json (input filename with ".json" appended)

Example:
  $0 -p scan_000303 input.txt
  # writes: input.txt.json
EOF
}

prefix="scan_000303"
infile=""

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--prefix)    prefix="${2:-}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    --)             shift; break ;;
    -*)
      echo "Unknown option: $1" >&2
      usage; exit 2
      ;;
    *)
      if [[ -z "${infile}" ]]; then infile="$1"; else
        echo "Unexpected extra argument: $1" >&2; usage; exit 2
      fi
      shift
      ;;
  esac
done

if [[ -z "${infile}" ]]; then
  usage; exit 2
fi

outfile="$(basename ${infile}).${prefix}.json"

awk -v prefix="$prefix" '
BEGIN {
  print "{"
  print "  \"root_directory\": \"/nrs/hess/Hayworth/DATA_Wafer66_ForRenderTest\","
  print "  \"owner\": \"hess_wafer_66\","
  print "  \"project\": \"test_b\","
  print "  \"stack\": \"w66_s000_r00\","
  print "  \"render_host\": \"em-services-1.int.janelia.org\","
  print "  \"resolution_x\": 8.0,"
  print "  \"resolution_y\": 8.0,"
  print "  \"resolution_z\": 8.0,"
  print "  \"sfov_info_list\": ["
  first = 1
}
# Skip empty lines and comments
/^[[:space:]]*$/ || /^[[:space:]]*#/ { next }

{
  path = $1
  gsub(/\\/, "/", path)        # backslashes -> slashes
  gsub(/"/, "\\\"", path)      # escape quotes for JSON
  if (prefix != "") path = prefix "/" path

  x = $2 + 0
  y = $3 + 0

  if (!first) printf(",\n")
  first = 0
  printf("    { \"path\": \"%s\", \"x\": %.3f, \"y\": %.3f }", path, x, y)
}
END {
  print "\n] }"
}
' "$infile" > "$outfile"

echo "Wrote JSON to: $outfile"