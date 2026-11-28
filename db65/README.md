# DB65

A dBASE II style database for the SBC65 FPGA computer (48K RAM) running the OS-65D V3.3 ROM DOS. It is written in 65C02 assembler and uses any 80-column VT100 terminal on the console: the FPGA's built-in screen, PuTTY, or the CYD and JC3248 terminals.

- **Commands:** typed at a dot prompt (`.`), as in dBASE II.
- **Files:** each database is an ordinary DOS file, so `DI` lists it and `DE` deletes it.
- **Disk access:** records are read and written one track (2K) at a time, so a file can be bigger than memory, up to 32 tracks (64K).
- **Fields:** up to 20 fields per record.
  - **C** (text, up to 64 characters).
  - **N** (number, up to 18 digits, with decimal places).
  - **D** (date, typed and shown as dd/mm/yyyy).
  - **L** (logical, Y/N).
- **Records:** up to 1,000 characters long.
- **Arithmetic:** decimal, with 12 significant digits (the same as CALC65).

## Loading and running it

1. At the DOS prompt, type `HL` and send `DB65.HEX`. HL finishes by itself.
2. Type `GO 3B00`.
3. Save it to disk once with `MS 3B00 83FF DB65` (10 tracks). After that, `MR DB65` loads and starts it.

The screen starts at 24 lines. For the FPGA's own 80 × 32 screen use `SET LINES 32`, then save the program again so it starts that way. (The setting is the byte at `$3B03`.)

## A first session

```
. CREATE PEOPLE
Field  1: NAME,C,20
Field  2: TOWN,C,15
Field  3: AGE,N,3
Field  4: SALARY,N,9,2
Field  5: BORN,D
Field  6: MEMBER,L
Field  7:                      (RETURN to finish)
Room for how many records? 100
Created. Room for 131 records.
. APPEND                       (a form for each new record)
. LIST NAME, TOWN FOR AGE > 30
. REPORT NAME, SALARY FOR MEMBER
. SORT ON NAME TO BYNAME
```

## Commands

Commands can be cut to their first four letters: `DISP` for `DISPLAY`, `REPL` for `REPLACE`.

| Command | What it does |
|---|---|
| `CREATE name` | Makes a new database. It asks for the fields as `NAME,TYPE,WIDTH,DECIMALS` and for how many records it must hold. If the name already exists, it asks before replacing it. |
| `USE name` | Opens a database. `USE` on its own (or `CLOSE`) closes it. |
| `APPEND` | Adds records on a form, one after another. Press RETURN on an empty record, or `^W`, to stop. |
| `APPEND BLANK` | Adds one empty record. |
| `EDIT [n]` | Changes record n (or the current one) on a form. |
| `BROWSE` | A table of records. Arrows move, `^C`/`^R` page, RETURN edits one, `^U` marks it deleted, ESC leaves. |
| `LIST [scope] [items] [OFF] [FOR c]` | Lists records. The items are fields or expressions separated by commas. `OFF` hides the record numbers. |
| `DISPLAY ...` | The same as `LIST`, but for the current record unless you give a scope or `FOR`. |
| `LIST STRUCTURE` | The fields and the file size. |
| `REPORT [fields] [scope] [FOR c]` | Columns with headings, totals of the number fields, and a record count. |
| `GO n`, `GO TOP`, `GO BOTTOM`, or just `n` | Moves to a record. |
| `SKIP [n]` | Moves n records forward, or back if n is negative. |
| `LOCATE [scope] FOR c` | Finds the first record that matches. `CONTINUE` finds the next one. |
| `REPLACE [scope] field WITH value [, field WITH value ...] [FOR c]` | Changes fields. |
| `DELETE [scope] [FOR c]` | Marks records for deletion (they show `*`). `RECALL` unmarks them. |
| `PACK` | Removes the marked records for good. |
| `ZAP` | Removes all the records (it asks first). |
| `COUNT [scope] [FOR c]` | Counts records. |
| `SUM [items] [FOR c]` and `AVERAGE [items] [FOR c]` | Totals and averages. With no items, every number field is used. |
| `SORT ON field TO name [DESCENDING]` | Writes a sorted copy of the file in use to a new file. |
| `? value, value` | Prints values. You can use it as a calculator. |
| `DIR [B:]` | The directory of the default drive, or of the drive given (the DOS `DI`). |
| `SET DEFAULT TO B` | The drive for file names without one (A–D). |
| `SET LINES n` | Screen lines (12–60). |
| `HELP` | A summary of the commands. |
| `QUIT` | Back to the DOS. |

**Scope** is `ALL`, `NEXT n` or `RECORD n`:

- `LIST`, `REPORT`, `COUNT`, `SUM`, `AVERAGE` and `LOCATE` use all the records unless told otherwise.
- `DISPLAY`, `DELETE`, `RECALL` and `REPLACE` use the current record, but all records once you add `FOR`.

Long listings stop after each screenful. Press any key to go on, or ESC to stop. ESC also stops a long `REPLACE` or `COUNT`.

## Drives

Every file name can start with its drive, as in dBASE II: `USE B:PEOPLE`, `CREATE C:STOCK`, `SORT ON NAME TO B:BYNAME`. A name without a drive is on the default drive.
- **Default drive:** the one the DOS was on when DB65 started. `SET DEFAULT TO B` changes it.
- **The file in use:** DB65 remembers which drive it is on. `LIST STRUCTURE` shows it as `B:PEOPLE`.
- **Two drives at once:** `SORT` can read a file on one drive and write the sorted copy to another.
- **On quitting:** DB65 puts the DOS back on the drive it started on.

## The form (APPEND and EDIT)

| Key | What it does |
|---|---|
| Typing | Overwrites the characters. When a field is full, the cursor moves to the next field. The first key typed into a number or date field clears it first. |
| RETURN, Down arrow | Next field. RETURN on the last field saves the record and goes on to the next one (with APPEND, a new blank record). |
| Up arrow | Previous field |
| Left / Right arrows | Move within the field |
| Backspace | Moves back one character and blanks it |
| `^G` | Deletes the character at the cursor |
| `^Y` | Clears the field |
| `^U` | Marks or unmarks the record for deletion |
| `^W` | Saves and leaves |
| ESC | Leaves without saving this record |
| `^C` / `^R` | Saves and moves to the next / previous record |

The arrow keys can also be typed as `^E ^X ^S ^D`.

Each field is checked when you leave it:

- Numbers are right-aligned with their decimal places.
- Dates must be real dates in dd/mm/yyyy (31/04 is refused).
- Logical fields take Y, N, T or F.

## Expressions

| What | How to write it |
|---|---|
| Values | Field names, numbers (`12.5`, `1E6`), text in `"..."` or `'...'`, `.T.` and `.F.` |
| Arithmetic | `+ - * /` and brackets. `+` also joins text. |
| Comparisons | `= <> # < > <= >=` |
| `a $ b` | True if the text `a` is inside `b` |
| Logic | `.AND.`, `.OR.`, `.NOT.` |

Text comparisons work as in dBASE: they compare only as many letters as the right-hand value has, so `NAME = "Sm"` matches "Smith". Dates compare in date order.

| Function | What it gives |
|---|---|
| `UPPER(c)`, `LOWER(c)`, `TRIM(c)` | The text in capitals, in small letters, or without trailing spaces |
| `LEN(c)` | Length of the text |
| `SUBSTR(c, start [, length])` | Part of the text |
| `VAL(c)`, `STR(n [, width [, decimals]])` | Text to number, and number to text |
| `INT(n)`, `ABS(n)`, `ROUND(n, decimals)` | Whole part, size without sign, rounding |
| `RECNO()`, `DELETED()` | Current record number, and whether it is marked for deletion |
| `CTOD("dd/mm/yyyy")`, `DTOC(date)` | Text to date, and date to text |
| `IIF(test, a, b)` | `a` if the test is true, otherwise `b` |
| `SPACE(n)` | n spaces |

Examples:

```
LIST NAME, SALARY*12 FOR TOWN = "Ryde" .AND. MEMBER
REPLACE ALL SALARY WITH ROUND(SALARY*1.05, 2) FOR AGE > 40
LIST FOR "Smith" $ NAME .OR. BORN < CTOD("01/01/1970")
? DTOC(BORN), UPPER(TRIM(NAME)) + "!", IIF(AGE > 50, "senior", "")
```

## The file on disk

`CREATE` makes the file with the DOS `MS` command, so the DOS allocates its tracks and directory entry. After that DB65 reads and writes sector 1 of each track (8 pages) with `CA` and `SA`.

- **Track 0:** the first 512 bytes are the header ("DB65", the record count, the record length and the field definitions). The rest of the track holds records.
- **Records:** each is a delete flag (`*` or space) followed by the fields as text. Numbers are stored right-aligned and dates as YYYYMMDD. A record never crosses a track.

Changes are written back after every command, so the file on disk is always up to date at the dot prompt.

## Memory used

| Address | What |
|---|---|
| `$3B00-$83F0` | The program (`MS 3B00 83FF` saves it) |
| `$83F1-$8B3B` | Its variables |
| `$9000-$9FFF` | Two track buffers |
| `$A000` | File header |
| `$A200` | Record |
| `$A600` | Directory |
| `$A800-$AFFF` | Form and text work area |
| `$A800-$BFFF` | Sort keys (only while sorting) |
| `$30-$AF` | Zero page, saved at the start and put back on quitting |

## Limits and notes

- It is for the FPGA version only. The real SBC has 32K of RAM and its ACIA at `$8000`.
- `SORT` keeps the first 12 characters of a text key, so two keys that differ only after that may come out in either order.
- `SORT` sorts at most about 400–500 records, depending on the key. On a 270-record file it takes about 8 seconds at 1 MHz, plus the disk time.
- Each `APPEND BLANK` writes the record's track and the header, so it takes about a second on the SD card.
- `SORT` copies records marked for deletion too. `PACK` first if you don't want them.
- There are no index files or multiple open files. To make a bigger file, `CREATE` it and copy the records over.

## Building from source

```
ca65 --cpu 65C02 DB.S -o DB.o
ld65 -C db.cfg DB.o -o DB.BIN
```

`DB.S` includes these files:

| File | What it holds |
|---|---|
| `BCD.S` | The decimal maths (shared with CALC65) |
| `DBIO.S` | Console, line input and DOS calls |
| `DBFILE.S` | Tracks, records and the file header |
| `DBEXPR.S` | Expressions |
| `DBCMD.S` | The dot-prompt commands |
| `DBSCR.S` | The form and BROWSE |

The `tools/` folder has the Python emulator used for testing (`pip install py65 pyte pillow`). It simulates the DOS `CA`, `SA`, `MS` and `DI` commands on a disk held in memory.
