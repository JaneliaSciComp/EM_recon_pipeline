#!/bin/bash

if (( $# != 1 )); then
  printf "\nUSAGE: %s <VM external IP>\n\n" "$(basename "$0")"
  exit 1
fi

IP="${1}"
IP_HOST="${IP}%3A8080"
PME="/render-ws/view/point-match-explorer.html?renderStackOwner=hess_wafers_60_61"

URL="http://${IP}:8080${PME}&renderDataHost=${IP_HOST}&dynamicRenderHost=${IP_HOST}&ndvizHost=${IP_HOST}"

printf "\n%s\n\n" "${URL}"