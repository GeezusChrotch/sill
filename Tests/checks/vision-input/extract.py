"""Compile the actual display/input transforms without UIKit, preserving method bodies."""
from pathlib import Path

def method(path, signature):
    text = Path(path).read_text()
    start = text.index(signature)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

video = method('iOSClient/HEVCDisplayView.swift', 'static func videoRect(')
normalized = method('iOSClient/InputOverlay.swift', 'private func normalized(').replace('private func', 'func', 1)
print('import Foundation\nimport CoreGraphics')
print('enum HEVCDisplayView {\n' + video + '\n}')
print('struct ActualInputMapper {\nlet bounds: CGRect\nlet videoSize: CGSize')
print('var videoRect: CGRect { HEVCDisplayView.videoRect(in: bounds, videoSize: videoSize) }')
print(normalized + '\n}')
