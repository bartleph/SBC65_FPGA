# OS-65D ROM DOS commands

The commands in the ROM DOS (`rom/ROM.S`, `rom/DOSX.S`, `rom/SD.S`, `rom/DIS.S`), for this FPGA and the real SBC.

How to read the table:

- `[ ]` means the part is optional.
- Addresses (`mmmm`, `ssss`, `eeee`) and track numbers (`tt`) are in hex.
- ESC or Ctrl-C stops a long listing, and space pauses it.

## Loading and running programs

| Command | What it does |
|---|---|
| `BA` | Start BASIC |
| `AS` | Start the Assembler |
| `EM` | Start the Extended Monitor |
| `RE A` / `RE B` / `RE E` / `RE M` | Go back into the Assembler / BASIC / EM / the monitor without reloading it |
| `FT` | Start Forth from the ROM at `$A000` |
| `GO mmmm` | Run code at `mmmm` (the program can return to DOS with RTS) |
| `LO name` / `LO tt` | Load a file, or the file at track `tt`, into the workspace |
| `PU name` / `PU tt` | Save the workspace back to that file or track |
| `XQ name` | Load a file and run it |
| `MS ssss eeee name[@xxxx]` | Save memory `ssss`–`eeee` as a named machine-code file. With `@xxxx` it loads back at `xxxx` |
| `ML name` | Load a machine-code file saved with `MS` |
| `MR name` | Load a machine-code file and run it |
| `HL` | Load a hex file sent to the console. See the notes below |

### HL formats

`HL` accepts both of these formats, even mixed in one file:

- **Intel HEX:** `:` records.
- **MOS Technology checksum:** `;` records. This is the OSI Assembler's checksum output.

While it loads:

- Each good record prints `.`.
- A record with a bad checksum prints `X`.
- The load ends on an end-of-file record, after about 2 seconds of silence once something has loaded, or on ESC.
- It then prints `LOADED ssss-eeee`, plus `BAD: nn` if any records failed.

## Files and directory

| Command | What it does |
|---|---|
| `DI` | Directory sorted by track, then the free tracks |
| `DI tt` | Sector map of track `tt` |
| `RN old new` | Rename a file |
| `DE name` | Delete a file (asks `SURE?`) |
| `TY name` | Type a text file. Assembler source, BASIC and Forth screens are shown readably |
| `SY N` / `SY V` | List the assembler symbol table sorted by name / by value |

## Disks and drives

| Command | What it does |
|---|---|
| `SE A` … `SE D` | Select the drive |
| `MO` | List which SD-card disk images are mounted |
| `MO d n` | Mount disk image `n` (0–255) on drive `d`, e.g. `MO B 12` |
| `CO s d [tt[-tt]]` | Copy tracks from drive `s` to drive `d`, either all of them or a range |
| `VE [tt[-tt]]` | Verify: read every sector |
| `IN tt` | Format one track |
| `IN` | Format the whole disk (asks `ARE YOU SURE?`) |
| `HO` | Move the head back to track 0 |
| `CA mmmm=tt,s` | Load sector `s` of track `tt` into memory at `mmmm` |
| `SA tt,s=mmmm/p` | Save `p` pages of memory, starting at `mmmm`, as sector `s` of track `tt` |
| `EX mmmm=tt` | Read a whole raw track into memory at `mmmm` |
| `DT` | Show the disk timing |
| `DT G` | Gotek timing (head 0 ms, step 3 ms) |
| `DT R` | Real-drive timing (head 40 ms, step 8 ms) |
| `DT hh ss` | Your own head and step delays in ms (decimal 0–255) |
| `PX` | Print the disk PIA values for each drive (diagnostic) |

`DT`, `PX` and `HO` are for floppy and Gotek drives on the real SBC. With SD-card disks you don't need them.

`CO`, `TY` and `VE` use `$7000`–`$77FF` as a sector buffer.

## Memory

| Command | What it does |
|---|---|
| `MD ssss [eeee]` | Hex dump of memory |
| `MF ssss eeee bb` | Fill memory with byte `bb` |
| `MM ssss eeee dddd` | Copy a block to `dddd`. Overlapping blocks are handled safely |
| `DA ssss [eeee]` | Disassemble 65C02 code (see the README) |

## Input and output

| Command | What it does |
|---|---|
| `IO ii,oo` | Set the input and output device masks |
| `ME iiii,oooo` | Set the memory input and output pointers |
