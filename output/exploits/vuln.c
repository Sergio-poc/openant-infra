#include <stdio.h>
#include <string.h>

void check_password(const char *input) {
    int authenticated = 0;
    char buffer[16];

    strcpy(buffer, input);

    if (authenticated) {
        printf("Access granted!\n");
    } else {
        printf("Access denied.\n");
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <password>\n", argv[0]);
        return 1;
    }
    check_password(argv[1]);
    return 0;
}
