#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d /tmp/scarlett-tests.XXXXXX)
clang++ -std=c++17 -fsanitize=address,undefined -I Shared Tests/ProtocolTests.cpp -o "$probe_dir/protocol-tests"
"$probe_dir/protocol-tests"
clang++ -std=c++17 -fsanitize=address,undefined -I Shared Tests/RouteSessionTests.cpp -o "$probe_dir/session-tests"
"$probe_dir/session-tests"
swiftc -module-cache-path "$probe_dir/swift-cache" App/RecoveryStore.swift Tests/RecoveryStoreTests.swift -o "$probe_dir/recovery-tests"
"$probe_dir/recovery-tests"
clang++ -std=c++17 -fsanitize=address,undefined -I Shared Tests/MixerTests.cpp -o "$probe_dir/mixer-tests"
"$probe_dir/mixer-tests"
swiftc -module-cache-path "$probe_dir/swift-cache" App/MixerState.swift Tests/MixerStateTests.swift -o "$probe_dir/mixer-state-tests"
"$probe_dir/mixer-state-tests"
python3 - <<'PY'
import plistlib
from pathlib import Path
p=plistlib.loads(Path('Driver/Info.plist').read_bytes())['IOKitPersonalities']['ScarlettDriver']
assert (p['idVendor'],p['idProduct'],p['bInterfaceNumber'],p['bInterfaceClass'])==(0x1235,0x8212,3,255)
assert p['IOProviderClass']=='IOUSBHostInterface'
print('PASS: USB matching restricted to Scarlett 4i4 Gen 3 vendor interface 3')
PY
