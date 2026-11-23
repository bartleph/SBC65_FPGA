/* ==========================================================================
 * hfe2sd.c - SD card images for the SBC65 SD driver, from Gotek HFE disk
 *            images. Builds with Dev-C++ (or any C compiler).
 *
 * Make a new card image (replaces everything):
 *     hfe2sd card.img PBDOS.HFE GAMES.HFE            slots 0, 1, ...
 *     hfe2sd card.img 0=PBDOS.HFE 12=WORK.HFE        chosen slots (- = empty)
 *   Write card.img to the card with Win32 Disk Imager.
 *
 * Add or replace disks on an existing card, leaving the other slots alone:
 *     hfe2sd -a card.img 12=WORK.HFE                 into an image file
 *     hfe2sd -a \\.\PhysicalDrive2 12=WORK.HFE       straight onto the card
 *
 * Remove a disk:
 *     hfe2sd -a \\.\PhysicalDrive2 12=-
 *
 * See what is on a card or image:
 *     hfe2sd -l \\.\PhysicalDrive2
 *
 * Label a card made by an older hfe2sd, keeping everything on it (it is
 * only accepted if slot 0 holds an OS-65D disk with a directory):
 *     hfe2sd -i \\.\PhysicalDrive2
 *
 * Find the card (Windows, as administrator): lists each physical drive
 * with its size, and marks cards made by hfe2sd:
 *     hfe2sd -d
 *
 * Writing straight to the card (Windows): run the Command Prompt as
 * administrator. Find the card's disk number in Disk Management (Win+X,
 * Disk Management - "Disk 2" means \\.\PhysicalDrive2). If Windows offers
 * to format or initialise the card, click Cancel. For safety -a and -l only work on a
 * card or image made by this version of hfe2sd (it puts an "SBC65 SD CARD"
 * label in block 0), so a wrong disk number is refused, not overwritten.
 *
 * Card layout (must match SD.S):
 *   block 0         label: "SBC65 SD CARD", then the number of slots
 *   block = 2048 + slot*3200 + track*80 + (sector-1)*5 + k
 *   k=0 info block: $A5, track (BCD), sector, pages; k=1-4 data.
 *
 * HFE decoding: the Gotek stores the OSI disk as FM cells (a clock pulse
 * every 4 cells, a data pulse half way = 0). The bits form the disk
 * ACIA's serial stream: start bit, 8 data bits (LSB first), even parity,
 * stop bit. Each track holds "CW" track "X", then sectors written as
 * $76 sector pages <pages*256 bytes> "GS".
 * ========================================================================== */
#ifndef _WIN32
#define _FILE_OFFSET_BITS 64
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <winioctl.h>
#endif

#define BLK       512
#define MAXSLOT   255
#define SLOTBLKS  3200L
#define FIRST     2048L
#define LABEL     "SBC65 SD CARD"

#ifdef _WIN32
#define SEEK64(f, o) _fseeki64(f, (__int64)(o), SEEK_SET)
#else
#define SEEK64(f, o) fseeko(f, (off_t)(o), SEEK_SET)
#endif

static unsigned char slotbuf[SLOTBLKS * BLK];   /* one disk image, 1.6 MB */

static long sblk(int trk, int sec, int k)       /* block within a slot */
{
    return trk * 80L + (sec - 1) * 5L + k;
}

/* ---- HFE track -> cell bits (one side, two revolutions) ---------------- */
static unsigned char *cells;
static long ncells;

static int load_track(const unsigned char *hfe, long hfelen, int trk)
{
    long lut = (hfe[18] | (hfe[19] << 8)) * 512L;
    long off = (hfe[lut + trk * 4] | (hfe[lut + trk * 4 + 1] << 8)) * 512L;
    long len =  hfe[lut + trk * 4 + 2] | (hfe[lut + trk * 4 + 3] << 8);
    long side_bytes = len / 2, i, j, n = 0;
    unsigned char *side = malloc(side_bytes + 512);

    for (i = 0; i < len; i += 512) {             /* side 0 = first 256 of 512 */
        long take = (len - i) / 2;
        if (take > 256) take = 256;
        if (off + i + take > hfelen) break;
        memcpy(side + n, hfe + off + i, take);
        n += take;
    }
    free(cells);
    ncells = n * 8 * 2;
    cells = malloc(ncells);
    for (j = 0; j < 2; j++)                      /* two revolutions */
        for (i = 0; i < n * 8; i++)
            cells[j * n * 8 + i] = (side[i >> 3] >> (i & 7)) & 1;
    free(side);
    return 1;
}

/* ---- FM pulses -> data bits ------------------------------------------- */
static unsigned char *bits;
static long nbits;

static void decode_fm(void)
{
    long i, last = -1;
    int have_data = 0;
    free(bits);
    bits = malloc(ncells / 2 + 16);
    nbits = 0;
    for (i = 0; i < ncells; i++) {
        long d;
        if (!cells[i]) continue;
        if (last < 0) { last = i; continue; }
        d = i - last;
        if (have_data) {                 /* data pulse seen: bit = 0 */
            bits[nbits++] = 0;
            last = i;
            have_data = 0;
        } else if (d < 3) {
            have_data = 1;
        } else {                         /* clock only: bit(s) = 1 */
            long k, n = (d + 2) / 4;
            if (n < 1) n = 1;
            for (k = 0; k < n && nbits < ncells / 2 + 8; k++) bits[nbits++] = 1;
            last = i;
        }
    }
}

/* ---- data bits -> ACIA bytes (8E1) ------------------------------------ */
static int *byt;          /* byte value, or | $100 on a framing/parity error */
static long nbyt;

static void decode_frames(void)
{
    long i = 0;
    free(byt);
    byt = malloc(sizeof(int) * (nbits / 11 + 16));
    nbyt = 0;
    while (i < nbits - 11) {
        if (bits[i] == 0) {
            int v = 0, k, ones = 0;
            for (k = 0; k < 8; k++) { v |= bits[i + 1 + k] << k; ones += bits[i + 1 + k]; }
            ones += bits[i + 9];
            byt[nbyt++] = ((ones & 1) == 0 && bits[i + 10] == 1) ? v : (v | 0x100);
            i += 11;
        } else {
            i++;
        }
    }
}

/* ---- parse one track and store its sectors in slotbuf ----------------- */
static int do_track(int trk, int *nsec, int *bad)
{
    long i, j;
    int hdr;
    *nsec = 0; *bad = 0;
    for (i = 0; i + 4 < nbyt; i++)
        if ((byt[i] & 0xFF) == 0x43 && (byt[i + 1] & 0xFF) == 0x57 && (byt[i + 3] & 0xFF) == 0x58)
            break;
    if (i + 4 >= nbyt) return 0;                 /* no track header */
    hdr = byt[i + 2] & 0xFF;
    j = i + 4;
    while (j + 3 < nbyt) {
        int sn = byt[j + 1] & 0xFF, pg = byt[j + 2] & 0xFF;
        if ((byt[j] & 0xFF) == 0x76 && sn == *nsec + 1 && pg >= 1 && pg <= 8
            && j + 3 + pg * 256L <= nbyt) {
            long o = sblk(trk, sn, 0) * BLK, k;
            slotbuf[o] = 0xA5; slotbuf[o + 1] = (unsigned char)hdr;
            slotbuf[o + 2] = (unsigned char)sn; slotbuf[o + 3] = (unsigned char)pg;
            for (k = 0; k < pg * 256L; k++) {
                int v = byt[j + 3 + k];
                if (v & 0x100) (*bad)++;
                slotbuf[sblk(trk, sn, 1 + (int)(k / 512)) * BLK + (k % 512)] = (unsigned char)v;
            }
            (*nsec)++;
            j += 3 + pg * 256L;
            if (*nsec == 15) break;
            continue;
        }
        j++;
    }
    return 1;
}

/* fill slotbuf from an HFE file ("-" = empty disk). 0 on error. */
static int convert(const char *name, int slot)
{
    unsigned char *hfe;
    long len;
    int trk, ntrk, total = 0;
    FILE *f;

    memset(slotbuf, 0, sizeof slotbuf);
    if (strcmp(name, "-") == 0) {
        printf("Slot %d: emptied\n", slot);
        return 1;
    }
    f = fopen(name, "rb");
    if (!f) { perror(name); return 0; }
    fseek(f, 0, SEEK_END); len = ftell(f); fseek(f, 0, SEEK_SET);
    hfe = malloc(len);
    if (fread(hfe, 1, len, f) != (size_t)len) { perror(name); fclose(f); return 0; }
    fclose(f);
    if (len < 1024 || memcmp(hfe, "HXCPICFE", 8) != 0) {
        fprintf(stderr, "%s: not an HFE (v1) file\n", name); free(hfe); return 0;
    }
    ntrk = hfe[9] > 40 ? 40 : hfe[9];
    printf("Slot %d%s: %s (%d tracks)\n", slot,
           slot < 4 ? (slot == 0 ? " (A)" : slot == 1 ? " (B)" : slot == 2 ? " (C)" : " (D)") : "",
           name, hfe[9]);
    for (trk = 0; trk < ntrk; trk++) {
        int ns, bad;
        load_track(hfe, len, trk);
        decode_fm();
        decode_frames();
        if (!do_track(trk, &ns, &bad)) continue;
        total += ns;
        if (bad) printf("  track %02d: %d sector(s), %d byte(s) with parity errors\n", trk, ns, bad);
    }
    printf("  %d sectors copied\n", total);
    free(hfe);
    return 1;
}

/* ---- block I/O on an image file or a raw card ------------------------- */
/* Whole 512-byte blocks at block offsets only, so a raw card works too.
 * On Windows a \\.\PhysicalDriveN path is opened with CreateFile (the C
 * library's fopen cannot open a physical drive). */
typedef struct {
    FILE *f;
#ifdef _WIN32
    HANDLE h;
#endif
} CARD;

#ifdef _WIN32
static void winerr(const char *what)
{
    char msg[256];
    DWORD e = GetLastError();
    msg[0] = 0;
    FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, e, 0,
                   msg, sizeof msg, NULL);
    fprintf(stderr, "%s: Windows error %lu: %s", what, (unsigned long)e, msg);
    if (e == 5) fprintf(stderr, "(run the Command Prompt / PowerShell as administrator)\n");
}
#endif

static int card_open(CARD *c, const char *path, int write)
{
    c->f = NULL;
#ifdef _WIN32
    c->h = INVALID_HANDLE_VALUE;
    if (strncmp(path, "\\\\.\\", 4) == 0) {
        c->h = CreateFileA(path, GENERIC_READ | (write ? GENERIC_WRITE : 0),
                           FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
        if (c->h == INVALID_HANDLE_VALUE) { winerr(path); return 0; }
        return 1;
    }
#endif
    c->f = fopen(path, write ? "r+b" : "rb");
    if (!c->f) { perror(path); return 0; }
    setvbuf(c->f, NULL, _IONBF, 0);
    return 1;
}

static void card_close(CARD *c)
{
#ifdef _WIN32
    if (c->h != INVALID_HANDLE_VALUE) CloseHandle(c->h);
    c->h = INVALID_HANDLE_VALUE;
#endif
    if (c->f) fclose(c->f);
    c->f = NULL;
}

static int rdblk(CARD *c, long blk, unsigned char *buf, long n)
{
#ifdef _WIN32
    if (c->h != INVALID_HANDLE_VALUE) {
        LARGE_INTEGER o; DWORD got;
        o.QuadPart = (LONGLONG)blk * BLK;
        if (!SetFilePointerEx(c->h, o, NULL, FILE_BEGIN)) return 0;
        return ReadFile(c->h, buf, (DWORD)(n * BLK), &got, NULL) && got == (DWORD)(n * BLK);
    }
#endif
    if (SEEK64(c->f, (long long)blk * BLK) != 0) return 0;
    return fread(buf, BLK, n, c->f) == (size_t)n;
}

static int wrblk(CARD *c, long blk, const unsigned char *buf, long n)
{
#ifdef _WIN32
    if (c->h != INVALID_HANDLE_VALUE) {
        LARGE_INTEGER o; DWORD put;
        o.QuadPart = (LONGLONG)blk * BLK;
        if (!SetFilePointerEx(c->h, o, NULL, FILE_BEGIN)) return 0;
        if (!WriteFile(c->h, buf, (DWORD)(n * BLK), &put, NULL) || put != (DWORD)(n * BLK)) {
            winerr("write");
            return 0;
        }
        return 1;
    }
#endif
    if (SEEK64(c->f, (long long)blk * BLK) != 0) return 0;
    if (fwrite(buf, BLK, n, c->f) != (size_t)n) return 0;
    return fflush(c->f) == 0;
}

static int read_label(CARD *f, int *nslots)
{
    unsigned char b[BLK];
    if (!rdblk(f, 0, b, 1)) return 0;
    if (memcmp(b, LABEL, sizeof LABEL) != 0) return 0;
    *nslots = b[16] | (b[17] << 8);
    return 1;
}

static int write_label(CARD *f, int nslots)
{
    unsigned char b[BLK];
    memset(b, 0, BLK);
    memcpy(b, LABEL, sizeof LABEL);
    b[16] = nslots & 0xFF; b[17] = nslots >> 8;
    return wrblk(f, 0, b, 1);
}

/* slot=file argument -> slot number and file name */
static int parse_arg(const char *arg, int pos, int *slot, const char **name)
{
    const char *eq = strchr(arg, '=');
    *slot = pos;
    *name = arg;
    if (eq) { *slot = atoi(arg); *name = eq + 1; }
    if (*slot < 0 || *slot > MAXSLOT) {
        fprintf(stderr, "%s: slot must be 0-255\n", arg);
        return 0;
    }
    return 1;
}

static void usage(void)
{
    fprintf(stderr,
        "usage: hfe2sd card.img DISK0.HFE [DISK1.HFE] ...     new image, slots 0, 1 ...\n"
        "       hfe2sd card.img 0=PBDOS.HFE 12=WORK.HFE        new image, chosen slots\n"
        "       hfe2sd -a card 12=WORK.HFE [n=file ...]        add/replace (n=- empties)\n"
        "       hfe2sd -l card                                  list the slots\n"
        "       hfe2sd -d                                       list the drives (Windows)\n"
        "       hfe2sd -i card                                  label a card from an older hfe2sd\n"
        "  card = an image file, or the SD card itself as \\\\.\\PhysicalDriveN\n");
}

/* ---- -l: list the slots ----------------------------------------------- */
static int list_card(const char *path)
{
    CARD cd, *f = &cd;
    int nslots, s, used = 0;
    unsigned char info[BLK], dir[BLK];

    if (!card_open(f, path, 0)) return 1;
    if (!read_label(f, &nslots)) {
        fprintf(stderr, "%s: no SBC65 card label - make the card with this hfe2sd first\n", path);
        card_close(f); return 1;
    }
    printf("%s: %d slot(s)\n", path, nslots);
    for (s = 0; s < nslots; s++) {
        long base = FIRST + s * SLOTBLKS;
        int k, shown = 0;
        if (!rdblk(f, base + sblk(12, 1, 0), info, 1)) break;
        if (info[0] != 0xA5) {
            if (!rdblk(f, base + sblk(0, 1, 0), info, 1) || info[0] != 0xA5) continue;
            printf("  %3d  (no directory)\n", s); used++; continue;
        }
        used++;
        printf("  %3d ", s);
        for (k = 1; k <= 2; k++) {               /* directory: track 12 sectors 1-2 */
            int e;
            if (!rdblk(f, base + sblk(12, k, 0), info, 1) || info[0] != 0xA5) continue;
            if (!rdblk(f, base + sblk(12, k, 1), dir, 1)) continue;
            for (e = 0; e < 16 && shown < 4; e++) {
                char nm[15];
                int c;
                if (dir[e * 16] == '#') continue;
                memcpy(nm, dir + e * 16, 14); nm[14] = 0;
                for (c = 13; c >= 0 && nm[c] == ' '; c--) nm[c] = 0;
                printf(" %s", nm);
                shown++;
            }
        }
        printf("%s\n", shown == 4 ? " ..." : "");
    }
    printf("%d slot(s) in use\n", used);
    card_close(f);
    return 0;
}

/* ---- -a: add/replace slots in an existing card or image --------------- */
static int add_slots(const char *path, int n, char **args)
{
    CARD cd, *f = &cd;
    int nslots, a, slot, newn;
    const char *name;

    if (!card_open(f, path, 1)) return 1;
    if (!read_label(f, &nslots)) {
        fprintf(stderr, "%s: no SBC65 card label - refusing to write.\n"
                        "Make the card once with this hfe2sd (no -a), then -a works.\n", path);
        card_close(f); return 1;
    }
    newn = nslots;
    for (a = 0; a < n; a++) {
        if (!strchr(args[a], '=')) {
            fprintf(stderr, "%s: with -a give the slot, e.g. 12=%s\n", args[a], args[a]);
            card_close(f); return 1;
        }
        if (!parse_arg(args[a], 0, &slot, &name)) { card_close(f); return 1; }
        if (!convert(name, slot)) { card_close(f); return 1; }
        if (!wrblk(f, FIRST + slot * SLOTBLKS, slotbuf, SLOTBLKS)) {
            fprintf(stderr, "%s: write failed at slot %d (card too small, or not run as administrator?)\n",
                    path, slot);
            card_close(f); return 1;
        }
        if (slot + 1 > newn) newn = slot + 1;
    }
    if (newn != nslots && !write_label(f, newn)) {
        fprintf(stderr, "%s: could not update the label\n", path);
        card_close(f); return 1;
    }
    card_close(f);
    printf("%s updated.\n", path);
    return 0;
}

/* ---- new image -------------------------------------------------------- */
static int new_image(const char *path, int n, char **args)
{
    int a, slot, maxslot = -1;
    const char *name;
    CARD cd, *f = &cd;
    static unsigned char zero[FIRST * BLK];

    for (a = 0; a < n; a++) {
        if (!parse_arg(args[a], a, &slot, &name)) return 1;
        if (strcmp(name, "-") != 0 && slot > maxslot) maxslot = slot;
    }
    if (maxslot < 0) { fprintf(stderr, "no disks given\n"); return 1; }

    memset(f, 0, sizeof *f);
#ifdef _WIN32
    f->h = INVALID_HANDLE_VALUE;
#endif
    f->f = fopen(path, "wb");
    if (!f->f) { perror(path); return 1; }
    /* label + empty slots first, so the file has its full size */
    if (!wrblk(f, 0, zero, FIRST) || !write_label(f, maxslot + 1)) { perror(path); return 1; }
    memset(slotbuf, 0, sizeof slotbuf);
    for (slot = 0; slot <= maxslot; slot++)
        if (!wrblk(f, FIRST + slot * SLOTBLKS, slotbuf, SLOTBLKS)) { perror(path); return 1; }
    for (a = 0; a < n; a++) {
        parse_arg(args[a], a, &slot, &name);
        if (strcmp(name, "-") == 0) continue;
        if (!convert(name, slot)) { card_close(f); return 1; }
        if (!wrblk(f, FIRST + slot * SLOTBLKS, slotbuf, SLOTBLKS)) { perror(path); return 1; }
    }
    card_close(f);
    printf("%s written (%ld bytes). Write it to the SD card with Win32 Disk Imager.\n",
           path, (FIRST + (maxslot + 1) * SLOTBLKS) * BLK);
    return 0;
}

/* ---- -i: label a card made by an older hfe2sd (keeps its contents) --- */
static int label_card(const char *path)
{
    CARD cd, *f = &cd;
    unsigned char b[BLK];
    int ns, s, last = -1;

    if (!card_open(f, path, 1)) return 1;
    if (read_label(f, &ns)) {
        printf("%s already has the label (%d slots)\n", path, ns);
        card_close(f); return 0;
    }
    /* only a card whose slot 0 holds an OS-65D disk is accepted */
    /* (its directory, track 12 sector 1, has an info block $A5 $12 $01) */
    if (!rdblk(f, FIRST + sblk(12, 1, 0), b, 1) || b[0] != 0xA5 || b[1] != 0x12 || b[2] != 1) {
        fprintf(stderr, "%s: slot 0 does not hold an SBC65 disk - not labelled.\n"
                        "Check the drive number with hfe2sd -d.\n", path);
        card_close(f); return 1;
    }
    for (s = 0; s <= MAXSLOT; s++) {
        long base = FIRST + s * SLOTBLKS;
        if (!rdblk(f, base + sblk(0, 1, 0), b, 1)) break;
        if (b[0] == 0xA5) { last = s; continue; }
        if (!rdblk(f, base + sblk(12, 1, 0), b, 1)) break;
        if (b[0] == 0xA5) last = s;
    }
    if (!write_label(f, last + 1)) {
        fprintf(stderr, "%s: could not write the label\n", path);
        card_close(f); return 1;
    }
    card_close(f);
    printf("%s labelled (%d slot(s)); its disks are unchanged.\n", path, last + 1);
    return 0;
}

/* ---- -d: list the physical drives (Windows) -------------------------- */
static int list_drives(void)
{
#ifdef _WIN32
    int n, found = 0;
    for (n = 0; n < 32; n++) {
        char path[32];
        CARD cd;
        GET_LENGTH_INFORMATION li;
        DWORD got;
        int ns;
        double gb = 0;
        sprintf(path, "\\\\.\\PhysicalDrive%d", n);
        cd.f = NULL;
        cd.h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                           NULL, OPEN_EXISTING, 0, NULL);
        if (cd.h == INVALID_HANDLE_VALUE) {
            if (GetLastError() == 5) {
                printf("%s: access denied - run as administrator\n", path);
                found++;
            }
            continue;
        }
        found++;
        if (DeviceIoControl(cd.h, IOCTL_DISK_GET_LENGTH_INFO, NULL, 0, &li, sizeof li, &got, NULL))
            gb = li.Length.QuadPart / 1e9;
        printf("%-20s %7.1f GB  %s\n", path, gb,
               read_label(&cd, &ns) ? "SBC65 card" : "");
        card_close(&cd);
    }
    if (!found) printf("no drives found\n");
    return 0;
#else
    fprintf(stderr, "-d is for Windows\n");
    return 1;
#endif
}

int main(int argc, char *argv[])
{
    if (argc >= 2 && strcmp(argv[1], "-d") == 0)
        return list_drives();
    if (argc >= 3 && strcmp(argv[1], "-i") == 0)
        return label_card(argv[2]);
    if (argc >= 3 && strcmp(argv[1], "-l") == 0)
        return list_card(argv[2]);
    if (argc >= 4 && strcmp(argv[1], "-a") == 0)
        return add_slots(argv[2], argc - 3, argv + 3);
    if (argc >= 3 && argv[1][0] != '-')
        return new_image(argv[1], argc - 2, argv + 2);
    usage();
    return 1;
}
