# Module `ProiProtocol::proi`
## Struct `PROI`
PROI token based on the Sui blockchain.
```rust
    struct PROI has drop {}
```

## Function `mint`
Minting PROI.
```rust
public entry fun mint(
    treasury_cap: &mut TreasuryCap<PROI>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext
)
```
<details>
<summary>Parameter</summary>

- `treasury_cap`: PROI Token capability object
- `amount`: minting amount
- `recipient`: token receiver

</details>