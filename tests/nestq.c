/* Client for tests/ipc.py. One shot: connect, send the command, print the body.
 * A warm server is what makes this cheaper than hyprctl; this program only
 * exists so the shell does not pay for a python start on every query. */
#include <arpa/inet.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: nestq SOCKET COMMAND...\n");
        return 2;
    }

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
        return 1;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    if (strlen(argv[1]) >= sizeof(addr.sun_path)) {
        fprintf(stderr, "nestq: socket path too long\n");
        return 1;
    }
    memcpy(addr.sun_path, argv[1], strlen(argv[1]));
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "nestq: connect: %s\n", strerror(errno));
        return 1;
    }

    size_t len = 0;
    for (int i = 2; i < argc; i++)
        len += strlen(argv[i]) + 1;
    char* cmd = malloc(len + 1);
    if (!cmd)
        return 1;
    cmd[0] = 0;
    for (int i = 2; i < argc; i++) {
        if (i > 2)
            strcat(cmd, " ");
        strcat(cmd, argv[i]);
    }
    /* One line on the wire. A Lua snippet keeps the newlines the shell
     * argument had; the server reads up to the first of them, so a snap
     * written across lines would arrive as just its first line. */
    for (char* p = cmd; *p; p++) {
        if (*p == '\n' || *p == '\r')
            *p = ' ';
    }
    strcat(cmd, "\n");
    size_t off = 0;
    size_t total = strlen(cmd);
    while (off < total) {
        ssize_t n = write(fd, cmd + off, total - off);
        if (n < 0) {
            free(cmd);
            return 1;
        }
        off += (size_t)n;
    }
    free(cmd);

    uint32_t be = 0;
    off = 0;
    while (off < 4) {
        ssize_t n = read(fd, (char*)&be + off, 4 - off);
        if (n <= 0)
            return 1;
        off += (size_t)n;
    }
    uint32_t nbytes = ntohl(be);
    while (nbytes > 0) {
        char buf[65536];
        size_t chunk = nbytes < sizeof(buf) ? nbytes : sizeof(buf);
        ssize_t n = read(fd, buf, chunk);
        if (n <= 0)
            return 1;
        if (fwrite(buf, 1, (size_t)n, stdout) != (size_t)n)
            return 1;
        nbytes -= (uint32_t)n;
    }
    return 0;
}
