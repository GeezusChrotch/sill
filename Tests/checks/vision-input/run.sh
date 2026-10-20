#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
mkdir -p .build/checks/vision-input
python3 Tests/checks/vision-input/extract.py > .build/checks/vision-input/ActualInputMapper.swift
swiftc .build/checks/vision-input/ActualInputMapper.swift visionOSClient/VisionInputGeometry.swift visionOSClient/VisionWindowSizePolicy.swift Tests/checks/vision-input/main.swift -o .build/checks/vision-input/check
.build/checks/vision-input/check
