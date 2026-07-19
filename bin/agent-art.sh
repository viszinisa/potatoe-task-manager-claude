#!/bin/sh
# Renders completion ("tick") and question art as exact 10x10 grids.
# Filler is U+3000 (invisible), so hand-typing these reliably loses trailing
# padding when icons are concatenated. Always generate, never retype.
set -e

usage() {
    echo "usage: agent-art.sh tick [1-3] | agent-art.sh question" >&2
    exit 1
}

tick_rows='..........
........##
.......##.
......##..
.....##...
##..##....
.####.....
..##......
..........
..........'

question_rows='..........
..####....
.##..##...
.....##...
....##....
...##.....
...##.....
..........
...##.....
..........'

case "$1" in
    tick)
        rows=$tick_rows
        glyph='✅'
        count=${2:-1}
        ;;
    question)
        rows=$question_rows
        glyph='🟥'
        count=1
        ;;
    *) usage ;;
esac

case "$count" in
    1 | 2 | 3) ;;
    *) usage ;;
esac

echo "$rows" | while IFS= read -r row; do
    i=0
    while [ "$i" -lt "$count" ]; do
        printf '%s' "$row" | sed -e "s/#/${glyph}/g" -e 's/\./　/g'
        i=$((i + 1))
    done
    printf '\n'
done
