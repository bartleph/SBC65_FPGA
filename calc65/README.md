# CALC65

A SuperCalc 2 style spreadsheet for the SBC65 FPGA computer (48K RAM) running the OS-65D V3.3 ROM DOS. It is written in 65C02 assembler and draws on any 80-column VT100 terminal on the console: the FPGA's built-in screen, PuTTY, or the CYD and JC3248 terminals.

- **Grid:** 26 columns (A–Z) and 128 rows.
- **Numbers:** decimal (BCD) floating point with 12 significant digits, so 0.1 + 0.2 really is 0.3. The range is 1E-99 to 9.99E+98.
- **Memory:** about 11.7K for cell contents.
- **Recalculation:** one pass, row by row, after every entry (or only when you press `!`).

## Loading and running it

1. At the DOS prompt, type `HL` and send `CALC65.HEX`. HL finishes by itself.
2. Type `GO 4000`.
3. Save it to disk once with `MS 4000 6ABF CALC65`. After that, `MR CALC65` loads and starts it.

The screen starts at 24 lines. For the FPGA's own 80 × 32 screen use `/G L 32`, and then save the program again with the `MS` line above so it starts that way next time. (The setting is the byte at `$4003`.)

If you quit and start it again, the sheet that was in memory is still there. `/Z` clears it.

## The screen

```
        A        B        C   ...      column letters
  1 HOUSEHOLD BUDGET 2026              the sheet (the cursor cell is in reverse)
  ...
E10 SUM(E4:E8)                         cursor cell and what is in it
Width:9  Format:$  Free:10719 ...      column width, format, free memory, messages
>                                      the entry line
```

## Keys

| Key | What it does |
|---|---|
| Arrow keys, or Ctrl-E / Ctrl-X / Ctrl-S / Ctrl-D | Move the cursor (up, down, left, right). The screen scrolls when you reach the edge. |
| Any other printable key | Starts an entry in the cursor cell |
| Return | Stores the entry and stays on the cell |
| An arrow key during an entry | Stores the entry and moves to the next cell |
| Backspace / Delete | Deletes the last character of the entry |
| Ctrl-U | Clears the entry line |
| ESC | Cancels the entry |
| `=` | Go to a cell, for example `=B12` |
| `!` | Recalculate everything |
| `?` | Help screen |
| `/` | Command menu (see below) |

## What you can type into a cell

- **Text** starts with `"`, for example `"Total`. A plain word that isn't a formula is taken as text as well. Text that is too long for its column spills over into empty cells to its right.
- **Numbers:** `12`, `-3.5`, `.25`, `1E6`, `2.5E-3`.
- **Formulas** are anything else. There is no leading `=` (`=` is "go to", as in SuperCalc).

| Formulas | Meaning |
|---|---|
| `+ - * /` | Arithmetic |
| `^` | Whole-number powers, for example `2^10` or `A1^-2` |
| `( )` | Brackets |
| `A1` | A cell reference. Empty cells and text count as 0. |
| `$A$1`, `$A1`, `A$1` | A `$` part stays fixed when the formula is copied or replicated |
| `A1:C9` | A range, used inside the functions below |
| `= < > <= >= <>` | Comparisons: the answer is 1 (true) or 0 (false) |
| `SUM(...)` | Total. The arguments can be ranges, cells or expressions, separated by commas. |
| `AVERAGE(...)` | Average (also written `AV` or `AVG`) |
| `MIN(...)`, `MAX(...)` | Smallest and largest value |
| `COUNT(...)` | How many numbers there are (text and empty cells are not counted) |
| `ABS(x)` | Size without the sign |
| `INT(x)` | Whole number part, rounding towards 0 |
| `IF(test,then,else)` | `then` if the test isn't 0, otherwise `else` |

A cell shows `ERROR` in these cases:

- division by 0;
- a number too big for the range;
- a reference to a cell that shows `ERROR`;
- a reference lost by `/D` (it appears as `#REF` in the formula).

If a formula has a typing mistake, it says `ERROR IN FORMULA` and lets you correct it.

## Slash commands

| Command | What it does |
|---|---|
| `/B` | **Blank** a range, for example `B2:D9` (Return = the cursor cell) |
| `/C` | **Copy** a cell or range to another place. References are adjusted, except the `$` parts. |
| `/R` | **Replicate**: copy a cell or range into every position of a target range. `/R` on B1 with target `C1:F1` fills the row, and `/R` from `A1:C1` to `A2:A10` copies the row down. |
| `/D` | **Delete** the cursor's Row or Column. Formulas that refer past it are adjusted. |
| `/I` | **Insert** an empty Row or Column at the cursor (the last row or column must be empty) |
| `/E` | **Edit** the cursor cell (its text is put on the entry line) |
| `/F` | **Format**: `G`lobal, `C`olumn, or `E`ntry (a range of cells). See the format codes below. |
| `/G` | **Global**: `L` = screen lines (12–60), `A` = recalculate after each entry, `M` = only when you press `!` |
| `/S` | **Save** the sheet to disk by name, for example `BUDGET` (it uses the DOS `MS` command) |
| `/L` | **Load** a sheet by name (it checks that the file is a CALC65 sheet first) |
| `/Z` | **Zap**: clear the whole sheet |
| `/Q` | **Quit** to the DOS |

Format codes for `/F`:

| Code | Meaning |
|---|---|
| `G` | General: as many digits as fit |
| `$` | Two decimal places |
| `I` | Whole numbers |
| `L` | Left-aligned |
| `R` | Right-aligned |
| `D` | Back to the default |

You can combine a number format and an alignment, for example `$L`. For `/F G` and `/F C` you can type a width (1–72) instead of a code.

## Memory used

| Address | What |
|---|---|
| `$4000-$6ABF` | The program |
| `$6AC0-$6E5F` | Its variables |
| `$7700-$773F` | Sheet header: column widths and formats |
| `$7800-$91FF` | Cell table (2 bytes per cell) |
| `$9200-$BFFF` | Cell contents. Space freed by edits is reclaimed automatically when needed. |
| `$30-$AF` | Zero page, saved at the start and put back on quitting |

A saved sheet is the block from `$7700` up to the end of the cell contents, saved with `MS` and loaded with `ML`. Save and load always go through `/S` and `/L`.

## Building from source

```
ca65 --cpu 65C02 CALC.S -o CALC.o
ld65 -C calc.cfg CALC.o -o CALC.BIN
```

`CALC.S` includes `BCD.S` (the decimal maths), `CELLS.S` (cell storage), `EVAL.S` (the formula evaluator) and `CMDS.S` (the slash commands and disk).

## Test tools

`tools/` has the Python tools used to test CALC65 (they need `pip install py65 pyte pillow`):

- `emu.py` runs the program in a 65C02 emulator with a VT100 screen.
- `bcdtest.py` checks the decimal maths against Python's `decimal` module. It assembles `TBCD.S` first.
- `fixbr.py` turns branches that are too long into `JMP`s; the source is already fixed.

## Limits and notes

- It is for the FPGA version only. The real SBC has 32K of RAM and its ACIA at `$8000`.
- Recalculation is one pass in row order, as in SuperCalc. A formula that uses a cell further down or to the right may need a second `!`.
- Long recalculations run at 1 MHz: about 5 ms per formula.
