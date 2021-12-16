#!/bin/bash

set -e

echo """
before:
"""

grep nearline 0[1346]*.sh list_first_and_last_dats.sh check_tabs.py

sed -i '
  s@/nearline/flyem/data@/nearline/flyem2/data@g
' 0[1346]*.sh list_first_and_last_dats.sh check_tabs.py

echo """
after:
"""

grep nearline 0[1346]*.sh list_first_and_last_dats.sh check_tabs.py
