# SafeSwap — Website Content Draft

## Section 1: Hero

**Headline:**
Protect Your Token Launch from Rug Pulls and Whale Dumps

**Subheadline:**
SafeSwap is a Uniswap V4 hook that enforces sell-side rate limiting and progressive fees — so no single wallet can crash your token's price.

**CTA Button:**
Launch a Protected Pool →

**Secondary CTA:**
Read the Source Code ↗


## Section 2: The Problem

**Headline:**
The #1 Reason People Don't Buy New Tokens? Fear.

**Body:**
Over 50% of new tokens show scam-like patterns. $2B+ is lost to rug pulls and exploits every year. Even legitimate projects suffer when a single whale dumps their entire bag in one transaction.

**Three stat cards:**

Card 1:
$2B+
Lost to crypto scams yearly
(Source: Chainalysis Crypto Crime Report)

Card 2:
50%+
Of new tokens exhibit rug-pull patterns
(Source: Solidus Labs)

Card 3:
24 hours
Most rug pulls happen within the first day

**Closing line:**
Your investors deserve better. SafeSwap makes trust enforceable, not optional.


## Section 3: How It Works

**Headline:**
On-Chain Protection in 3 Steps

**Step 1:**
Create a Pool
Use the SafeSwap Factory to create a Uniswap V4 pool with built-in protection. Choose your token pair, set your limits, done.

**Step 2:**
Protection Activates Automatically
Every sell is checked against your configured limits. Rate limiting, cooldowns, and progressive fees kick in — enforced by the smart contract, not by trust.

**Step 3:**
Trade With Confidence
Traders see that your pool is SafeSwap-protected. No single wallet can dump more than your configured limit. Large sells pay higher fees that protect liquidity providers.


## Section 4: Features

**Headline:**
What SafeSwap Enforces

**Feature 1: Sell Rate Limiting**
Set a maximum sell amount per wallet per time window. For example: no wallet can sell more than 2% of total supply in 24 hours. Enforced on-chain, no exceptions.

**Feature 2: Cooldown Between Sells**
Prevent rapid-fire selling. Each wallet must wait a configurable period between sells — stopping bots and panic cascades.

**Feature 3: Progressive Fees**
Larger sells pay higher LP fees. Small retail sells pay the standard 0.30%. Whale-sized sells pay up to 5%. This protects liquidity providers and discourages dumps.

| Sell Size (% of supply) | Fee   |
|--------------------------|-------|
| < 0.1%                   | 0.30% |
| 0.1% – 0.5%             | 1.00% |
| 0.5% – 1.0%             | 3.00% |
| > 1.0%                   | 5.00% |

**Feature 4: Launch Protection Mode**
The most vulnerable period is right after launch. SafeSwap offers a separate, stricter set of limits for the first hours — tighter buy/sell caps, longer cooldowns. Once the launch window expires, normal limits take over automatically.

**Feature 5: Immutable Configuration**
Once a pool is created, its protection parameters cannot be changed — not even by the pool creator. This is trustless protection: the rules are set in stone.


## Section 5: For Token Launchers

**Headline:**
Build Trust Before Your First Trade

**Body:**
You know your project is legitimate. But your investors don't — and they've been burned before.

SafeSwap gives you a verifiable guarantee: your token's pool has on-chain protection against dumps. Not a promise. Not a Telegram message. A smart contract that physically prevents large sudden sells.

**What you get:**
- A Uniswap V4 pool with built-in anti-dump protection
- Verifiable on-chain — anyone can read the contract
- Configurable limits that match your tokenomics
- A trust signal that separates you from scams
- Free pool creation during our launch period

**How to create a protected pool:**
1. Go to the SafeSwap Factory contract on Arbiscan
2. Call `createPool` with your token address, paired token, and protection parameters
3. Add liquidity to your new pool
4. Share the pool link — investors can verify the protection on-chain

(Detailed guide coming soon)


## Section 6: For Traders

**Headline:**
Know Your Pool Is Protected Before You Buy

**Body:**
When you trade in a SafeSwap-protected pool, you know that:

- No wallet can dump more than the configured limit per day
- Large sellers pay higher fees that go to liquidity providers (that includes you, if you LP)
- The protection rules are immutable — the creator can't turn them off
- Everything is on-chain and verifiable

**How to check if a pool is SafeSwap-protected:**
Look for the hook address `0x66af5C4D7bA72dA6c635B26589C0af86353aE0C0` on the pool. If SafeSwap is the hook, the pool is protected.

(Pool directory coming soon)


## Section 7: Security & Trust

**Headline:**
Verified, Tested, Open Source

**Card 1: Verified on Arbiscan**
Both contracts are verified — anyone can read the source code and confirm it matches the deployed bytecode.
→ View SafeSwapHook on Arbiscan
→ View SafeSwapFactory on Arbiscan

**Card 2: 100% Test Coverage**
66 tests including fuzz testing with 10,000 random inputs. 100% line, statement, branch, and function coverage on both contracts.

**Card 3: Open Source**
The full source code is available on GitHub. Review it, fork it, contribute.
→ GitHub Repository

**Card 4: Immutable & Trustless**
Pool configurations are set once and cannot be changed. There is no admin key that can disable protection. The owner can only withdraw earned fees and authorize the factory — not modify pool rules.

**Known limitations (transparent disclosure):**
- Uses `tx.origin` for seller identification — works for 95%+ of wallets (EOA), but not for smart contract wallets (Gnosis Safe, AA wallets). Smart contract wallet support is planned.
- This contract has not been formally audited. It has been thoroughly tested but use at your own risk.
- SafeSwap protects against large sudden sells. It does not prevent gradual selling within the configured limits, nor does it protect against other types of exploits.


## Section 8: Footer

**Built by**
Kristiyan Petrov
[GitHub icon] https://github.com/zontak  |  [LinkedIn icon] https://www.linkedin.com/in/kristiyan-petrov-zontak/

**Contracts (Arbitrum One)**
SafeSwapHook: 0x66af5C4D7bA72dA6c635B26589C0af86353aE0C0
SafeSwapFactory: 0x7704377059CF4Eb88050445B78f1d6b1eb1fa78A

**Resources**
GitHub Repository
Arbiscan — Hook
Arbiscan — Factory
Security Policy

**Legal**
SafeSwap is open-source software provided as-is. It is not financial advice. Users are responsible for their own due diligence. Smart contracts carry inherent risk.


## SEO Metadata

**Title tag:**
SafeSwap — Anti-Rug & Anti-Whale Protection for Uniswap V4

**Meta description:**
Protect your token launch with on-chain sell rate limiting, progressive fees, and anti-whale controls. SafeSwap is a verified, open-source Uniswap V4 hook deployed on Arbitrum.

**Keywords:**
anti-rug pull, anti-whale, uniswap v4 hook, token launch protection, sell rate limiting, progressive fees, arbitrum, defi security, meme coin protection, safe token launch

**Open Graph:**
og:title — SafeSwap — Anti-Rug Protection for Uniswap V4
og:description — On-chain sell rate limiting and progressive fees to protect token launches from rug pulls and whale dumps.
og:type — website


## llms.txt

SafeSwap is an anti-rug and anti-whale protection hook for Uniswap V4, deployed on Arbitrum One.

It enforces sell-side rate limiting (max sell per wallet per time window), cooldowns between sells, and progressive fees (larger sells pay higher fees). Pool configurations are immutable after creation.

Contracts (Arbitrum One, verified on Arbiscan):
- SafeSwapHook: 0x66af5C4D7bA72dA6c635B26589C0af86353aE0C0
- SafeSwapFactory: 0x7704377059CF4Eb88050445B78f1d6b1eb1fa78A

Source code: https://github.com/zontak/SafeSwap
License: MIT

Built by Kristiyan Petrov.
