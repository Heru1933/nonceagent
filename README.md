# NonceAgent

**A proof-of-work free-mint NFT that only Agent ID holders can earn.**

Minting is free but not effortless. To mint, a wallet must (1) hold an
Agent ID (name.ai) and (2) present a nonce whose
`keccak256(contract, caller, mintIndex, nonce)` hash clears the difficulty
target. The puzzle is bound to the caller and to how many NFTs they have
already minted, so solutions cannot be shared between wallets, stockpiled
in advance, or replayed — every mint is fresh work performed by a verified
agent wallet. Solving happens entirely off-chain in the browser; only valid
solutions are ever submitted on-chain.

## Why Agent ID is core to the product

- `mint()` reverts unless the caller holds an Agent ID — checked live against
  the official SPACE ID Agent ID contract
  (`0x60b9262456de011f7d15a54cdd8c48baaa8b022f`, BNB Chain) on every call.
- Agent IDs are non-transferable and limited to one per user, and the PoW
  puzzle is per-wallet — together they make the mint Sybil-resistant twice
  over: one identity per person, and real compute per mint.
- The result is a fair-launch distribution primitive for the agent economy:
  no gas wars (failed attempts never touch the chain), no allowlist
  gatekeeping, no bot sniping with copied calldata.

## Deploy parameters (planned)

- Max supply: 3,333
- Max per wallet: 3
- Difficulty: 20 leading zero bits (~1M hashes, seconds in a browser)
- Mint price: 0 (gas only)

## Contract

- `src/NonceAgent.sol` — self-contained ERC-721 + PoW mint, no external
  dependencies, no owner/admin keys, no mint/pause/freeze backdoors.
- Tests: `test/NonceAgent.t.sol` (Foundry) — non-agent rejection, invalid
  nonce rejection, valid mint, replay protection (same nonce dies after one
  use), wallet-binding of solutions, per-wallet cap, transfers.
  Run: `forge test` (7/7 passing).

## Safety (hackathon red lines)

- No web QR / pairing-code login; the web page uses a standard injected
  wallet and the user signs and confirms every transaction themselves.
- No asset transfers beyond the user's own mint, no approvals, no promised
  returns. The NFT is a collectible proving an agent did the work.
- Contract is open-source and ownerless.

## Layout

- `src/NonceAgent.sol` — contract
- `test/NonceAgent.t.sol` — tests
- `web/index.html` — single-file frontend with an in-browser Web Worker
  solver (connect wallet → Solve & Mint → sign)

## Status

Built for the Binance Wallet × BNB Chain Agent ID Hackathon
(submission period 2026-11-18 → 2026-12-09 UTC). Deployment + BscScan
verification pending; the deployed address goes in `web/index.html`
(`NONCE_ADDR`) and in this README once live.
