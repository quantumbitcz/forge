# Scenario 10 — PHP SQL injection patch

`UserRepository::findByEmail($email)` string-concatenates `$email` into a raw SQL statement. Replace with a PDO prepared statement, add a PHPUnit test proving `'; DROP TABLE users; --` is neutralized.

Pipeline mode: `bugfix`.
