#!/bin/sh
# HDMI / USB digitizer as a mouse. Leaves an existing HID→HDMI map alone.
set -e
RC="${HOME}/.config/labwc/rc.xml"
SYS=/etc/xdg/labwc/rc.xml
mkdir -p "${HOME}/.config/labwc"
if [ ! -f "$RC" ]; then
    if [ -f "$SYS" ]; then
        cp "$SYS" "$RC"
    else
        printf '%s\n' '<?xml version="1.0"?>' \
            '<openbox_config xmlns="http://openbox.org/3.4/rc">' \
            '</openbox_config>' > "$RC"
    fi
fi
if grep -q 'Duals-touch' "$RC"; then
    exit 0
fi
python3 - "$RC" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text()
snippet = '''  <!-- Duals-touch: HDMI panel digitizer -> mouse -->
  <touch mapToOutput="HDMI-A-1" mouseEmulation="yes" />
'''
if '</openbox_config>' in text:
    text = text.replace('</openbox_config>', snippet + '</openbox_config>', 1)
else:
    sys.exit('cannot patch %s' % p)
p.write_text(text)
PY
