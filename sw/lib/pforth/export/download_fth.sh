#!/bin/bash
# download_fth.sh -- Download pForth .fth files from upstream
# Usage: cd export && bash download_fth.sh

BASE="https://raw.githubusercontent.com/philburk/pforth/master/fth"

FILES=(
    system.fth
    loadp4th.fth
    savedicd.fth
    forget.fth
    numberio.fth
    misc1.fth
    case.fth
    structure.fth
    strings.fth
    private.fth
    ansilocs.fth
    locals.fth
    math.fth
    condcomp.fth
    misc2.fth
    save-input.fth
    file.fth
    require.fth
    slashqt.fth
    member.fth
    c_struct.fth
    smart_if.fth
    filefind.fth
    see.fth
    wordslik.fth
    trace.fth
    termio.fth
    history.fth
)

for f in "${FILES[@]}"; do
    echo "Downloading $f ..."
    curl -sL "$BASE/$f" -o "fth/$f"
    if [ $? -ne 0 ]; then
        echo "FAIL: $f"
    fi
done

echo "Done. $(ls fth/*.fth | wc -l) files downloaded."
