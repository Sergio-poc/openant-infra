# Buffer Overflow – Stack Variable Overwrite

## Description
The `check_password` function in `vuln.c` uses `strcpy()` to copy user input into a 16-byte stack buffer without bounds checking. A local `int authenticated` variable sits adjacent on the stack.

## Objective
Demonstrate that an attacker can overwrite the `authenticated` variable by providing an input longer than 16 bytes, causing the program to print "Access granted!" without knowing the password.

## Expected Exploitation
Provide an argument longer than 16 characters to overflow `buffer` and overwrite `authenticated` with a non-zero value.
