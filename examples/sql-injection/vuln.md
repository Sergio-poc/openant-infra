# SQL Injection – Authentication Bypass

## Description
The `/login` endpoint in `app.py` constructs a SQL query by directly interpolating user-supplied `username` and `password` values using an f-string. No input sanitization or parameterized queries are used.

## Objective
Demonstrate that an attacker can bypass authentication and log in as `admin` without knowing the password.

## Expected Exploitation
Use a classic SQL injection payload in the username or password field (e.g., `' OR '1'='1' --`) to manipulate the WHERE clause and authenticate as any user.
