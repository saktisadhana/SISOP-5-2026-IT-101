int cursor = 0;
char color = 0x07;

void putInMemory(int segment, int address, char character);
int getChar();

/*
 * Final Challenge
 *
 * Commands:
 * - check
 * - add <a> <b>
 * - sub <a> <b>
 * - fac <n>
 * - season <name>
 * - triangle <n>
 * - clear
 * - about
 *
 * Season list:
 * - winter
 * - spring
 * - summer
 * - fall
 * - radiant
 *
 * Restrictions:
 * - no stdlib
 * - avoid division (/)
 * - avoid modulo (%)
 */

/* ─────────────────────────────────────────
   Low-level screen helpers
   ───────────────────────────────────────── */

void printChar(char c) {
    putInMemory(0xB800, cursor * 2,     c);
    putInMemory(0xB800, cursor * 2 + 1, color);
    cursor++;
}

void newline() {
    /* advance cursor to next multiple of 80 */
    int col = cursor - (cursor / 80) * 80;
    int spaces = 80 - col;
    int i;
    for (i = 0; i < spaces; i++) {
        printChar(' ');
    }
}

void printString(char *s) {
    while (*s) {
        printChar(*s);
        s++;
    }
}

void clearScreen() {
    int i;
    color = 0x07;
    cursor = 0;
    for (i = 0; i < 80 * 25; i++) {
        putInMemory(0xB800, i * 2,     ' ');
        putInMemory(0xB800, i * 2 + 1, 0x07);
    }
}

/* ─────────────────────────────────────────
   Keyboard input
   ───────────────────────────────────────── */

void readString(char *buf) {
    int i = 0;
    char c;
    while (1) {
        c = getChar();
        if (c == '\r' || c == '\n') {
            break;
        } else if (c == '\b') {
            /* backspace */
            if (i > 0) {
                i--;
                cursor--;
                printChar(' ');
                cursor--;
            }
        } else {
            buf[i] = c;
            i++;
            printChar(c);
        }
    }
    buf[i] = '\0';
}

/* ─────────────────────────────────────────
   String utilities
   ───────────────────────────────────────── */

int strcmp(char *a, char *b) {
    while (*a && *b && *a == *b) {
        a++;
        b++;
    }
    return (*a == '\0' && *b == '\0');
}

/* returns 1 if s starts with prefix */
int startsWith(char *s, char *prefix) {
    while (*prefix) {
        if (*s != *prefix) return 0;
        s++;
        prefix++;
    }
    return 1;
}

/* skip leading spaces, return pointer past prefix */
char *skipWord(char *s) {
    while (*s && *s != ' ') s++;
    while (*s == ' ') s++;
    return s;
}

int atoi(char *s) {
    int result = 0;
    int neg = 0;
    if (*s == '-') { neg = 1; s++; }
    while (*s >= '0' && *s <= '9') {
        result = result * 10 + (*s - '0');
        s++;
    }
    return neg ? -result : result;
}

void intToString(int n, char *buf) {
    char tmp[12];
    int i = 0;
    int j = 0;

    if (n < 0) {
        buf[j++] = '-';
        n = -n;
    }

    if (n == 0) {
        buf[j++] = '0';
        buf[j] = '\0';
        return;
    }

    while (n > 0) {
        tmp[i++] = '0' + (n - (n / 10) * 10); /* n % 10 without % */
        n = n / 10;
    }

    /* reverse into buf */
    while (i > 0) {
        buf[j++] = tmp[--i];
    }
    buf[j] = '\0';
}

/* ─────────────────────────────────────────
   Math
   ───────────────────────────────────────── */

/* factorial — 16-bit signed max ~32767, so fac(8)=40320 overflows */
int factorial(int n) {
    int result = 1;
    int i;
    for (i = 2; i <= n; i++) {
        result = result * i;
        if (result < 0) return -1; /* overflow sentinel */
    }
    return result;
}

/* ─────────────────────────────────────────
   Triangle
   ───────────────────────────────────────── */

void printTriangle(int n) {
    int row, col;
    for (row = 1; row <= n; row++) {
        for (col = 0; col < row; col++) {
            printChar('x');
        }
        newline();
    }
}

/* ─────────────────────────────────────────
   Main shell
   ───────────────────────────────────────── */

void main() {
    char cmd[64];
    char numBuf[12];
    int  a, b, result;

    clearScreen();

    printString("Welcome to Assistant's Last Gift");
    newline();
    printString("type 'help'");
    newline();
    newline();

    while (1) {
        printString("> ");
        readString(cmd);
        newline();

        /* ── check ── */
        if (strcmp(cmd, "check")) {
            printString("ok");

        /* ── add <a> <b> ── */
        } else if (startsWith(cmd, "add ")) {
            char *p = skipWord(cmd);   /* skip "add" */
            a = atoi(p);
            p = skipWord(p);           /* skip first number */
            b = atoi(p);
            result = a + b;
            intToString(result, numBuf);
            printString(numBuf);

        /* ── sub <a> <b> ── */
        } else if (startsWith(cmd, "sub ")) {
            char *p = skipWord(cmd);
            a = atoi(p);
            p = skipWord(p);
            b = atoi(p);
            result = a - b;
            intToString(result, numBuf);
            printString(numBuf);

        /* ── fac <n> ── */
        } else if (startsWith(cmd, "fac ")) {
            char *p = skipWord(cmd);
            a = atoi(p);
            result = factorial(a);
            if (result < 0 || result == 0) {
                printString("know your limit little bro.");
            } else {
                intToString(result, numBuf);
                printString(numBuf);
            }

        /* ── season <name> ── */
        } else if (startsWith(cmd, "season ")) {
            char *p = skipWord(cmd);
            if (strcmp(p, "winter")) {
                color = 0x09; /* bright blue */
                printString("winter mode");
            } else if (strcmp(p, "spring")) {
                color = 0x0A; /* bright green */
                printString("spring mode");
            } else if (strcmp(p, "summer")) {
                color = 0x0E; /* yellow */
                printString("summer mode");
            } else if (strcmp(p, "fall")) {
                color = 0x0C; /* bright red / orange */
                printString("fall mode");
            } else if (strcmp(p, "radiant")) {
                color = 0x0D; /* bright magenta / pink */
                printString("radiant mode");
            } else {
                printString("unknown season");
            }

        /* ── triangle <n> ── */
        } else if (startsWith(cmd, "triangle ")) {
            char *p = skipWord(cmd);
            a = atoi(p);
            printTriangle(a);

        /* ── clear ── */
        } else if (strcmp(cmd, "clear")) {
            clearScreen();

        /* ── help ── */
        } else if (strcmp(cmd, "help")) {
            printString("check add sub fac season triangle clear about");

        /* ── about ── */
        } else if (strcmp(cmd, "about")) {
            printString("Assistant's Last Gift - Final Challenge OS");

        } else {
            printString("unknown command");
        }

        newline();
    }
}
