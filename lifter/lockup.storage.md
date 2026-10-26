# Storage schema

Recovered from lifted bytecode: durability, key, value type, and access per
storage slot. Keys are shown by their `DataKey` variant name, recovered from
the symbol the builder reads out of the data section (falling back to the
`DataKey#<n>` discriminant when the name is not recoverable); a parameterized
key is a mapping, shown as `(key) -> value`; `?` marks a key encoding this
pass does not decode.

| Durability | Key | Type | Access |
|---|---|---|---|
| instance | ReserveA | i128 | write |
| instance | ReserveB | i128 | write |
| instance | TokenA | Address | read/write |
| instance | TokenB | Address | write |
| instance | TotalShares | i128 | write |
| persistent | Shares | (Address) -> i128 | read |
