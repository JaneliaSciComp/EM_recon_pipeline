#!/bin/bash

# BASE_SCP="scp -T -o ConnectTimeout=10 -o StrictHostKeyChecking=no"
BASE_SCP="scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no"

${BASE_SCP} "jeiss3.hhmi.org:/cygdrive/e/Images/Mouse/Y2022/M11/D02/Merlin-6257_22-11-02_235753_0-0-0.png" .
