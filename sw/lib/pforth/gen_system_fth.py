#!/usr/bin/env python3
"""Generate system_fth.h from system.fth for embedded runtime interpretation."""

import sys

with open('export/fth/system.fth', 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

# Remove save-forth onwards
idx = content.find('c" pforth.dic"')
if idx > 0:
    content = content[:idx]

# Remove 'include loadp4th.fth'
content = content.replace('include loadp4th.fth\n', '')

# Remove FREEZE (pForth save-related, not needed at runtime)
content = content.replace('FREEZE', '')

# Escape for C string
content = content.replace('\\', '\\\\')
content = content.replace('"', '\\"')
content = content.replace('\r', '\\r')
# Split lines with quotes for readability
lines = content.split('\n')
escaped_lines = []
for line in lines:
    escaped_lines.append('"' + line + '\\n"')
text = '\n'.join(escaped_lines)

# Write header
with open('system_fth.h', 'w') as f:
    f.write('/* system_fth.h -- pForth system.fth for runtime interpretation */\n')
    f.write('#ifndef SYSTEM_FTH_H\n')
    f.write('#define SYSTEM_FTH_H\n\n')
    f.write('static const char g_system_fth[] =\n')
    f.write(text + '\n;\n\n')
    f.write('#endif /* SYSTEM_FTH_H */\n')

print(f"Generated system_fth.h ({len(content)} bytes of Forth source)")
