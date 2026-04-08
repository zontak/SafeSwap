# Security

## Reporting Vulnerabilities

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT open a public GitHub issue**
2. Email: [security contact TBD]
3. Include: description, reproduction steps, and potential impact

We will acknowledge receipt within 48 hours and provide a timeline for a fix.

## Known Limitations

### tx.origin for seller identification

The hook uses `tx.origin` to identify sellers. This is a deliberate design choice:

- **Why**: `msg.sender` in hook callbacks is always the PoolManager, not the user. Using `tx.origin` identifies the EOA that initiated the transaction, which works with all existing Uniswap routers.
- **Limitation**: Smart contract wallets (multisigs, account abstraction wallets) resolve to the underlying EOA signer, not the wallet contract address. Rate limits are applied per-EOA, not per-smart-wallet.
- **Not exploitable for bypass**: An attacker cannot use a proxy contract to circumvent rate limits because `tx.origin` still resolves to their EOA.

### Supply caching

Token supply is cached for 100 blocks (~20 minutes on L2s). During rapid supply changes (mints/burns), the cached supply may be stale. This is conservative by design -- stale supply means tighter rate limits.

### Immutable pool configuration

Once `configurePool` is called, parameters cannot be changed. This is intentional for trustlessness -- pool creators cannot rug by weakening protections after launch.

## Audit Status

This contract has not been formally audited. Use at your own risk.
