#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
# Run the production launch handler and pending-selection resolver with deterministic app,
# catalog and capture stand-ins. No workspace activation, Accessibility, or capture occurs.
python3 - "$out/main.swift" <<'PY'
import pathlib, sys
source = pathlib.Path('Sources/SillHost/StreamCoordinator.swift').read_text()
start = source.index('        case .launchApp:', source.index('switch message.kind'))
end = source.index('        case .editableFocus:', start)
launch = source[start:end].split('\n', 2)[2]
start = source.index('    private func selectPendingAppWindow()')
end = source.index('    private func windowsChanged(', start)
resolver = source[start:end].replace('    private func', '    func')
harness = pathlib.Path('Tests/checks/app-selection/main.swift').read_text()
pathlib.Path(sys.argv[1]).write_text(harness.replace('/* LAUNCH */', launch).replace('/* RESOLVER */', resolver))
PY
swiftc -O -parse-as-library "$out/main.swift" -o "$out/check"
"$out/check"
