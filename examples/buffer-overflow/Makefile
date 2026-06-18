CC = gcc
CFLAGS = -fno-stack-protector -z execstack -no-pie -g

all: vuln

vuln: vuln.c
	$(CC) $(CFLAGS) -o vuln vuln.c

clean:
	rm -f vuln
