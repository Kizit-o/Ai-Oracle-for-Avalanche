# AI Oracle for Avalanche

AI Oracle for Avalanche is a trust-minimized off-chain computation system that enables Avalanche smart contracts to request AI-generated results through a verifiable commit–reveal protocol. It provides an end-to-end pipeline consisting of smart contracts, backend AI compute services, and a React-based dashboard for developers.


## Features

- Commit–Reveal verification of AI outputs
- Avalanche Fuji smart contract integration
- OpenAI/Llama-based off-chain computation
- Event-driven backend listener
- MetaMask-powered request submission
- Developer dashboard with real-time job tracking


## Architecture

1. **Frontend (React + Tailwind)**
   - Wallet connection
   - Submit requests
   - Track oracle status
   - Display results

2. **Backend (Node.js)**
   - Handles AI inference
   - Generates commitments via SHA-256
   - Listens to smart contract events
   - Sends results back on reveal

3. **Oracle Smart Contracts (Solidity)**
   - Receives on-chain requests
   - Stores commitments
   - Records reveal results
   - Emits events for the backend

4. **Verification Layer**
   - Commit-reveal scheme
   - Ensures results cannot be changed by backend


## Roadmap

- Phase 1: Architecture definition, repo setup
- Phase 2: Backend AI compute service
- Phase 3: Commit–reveal verification logic
- Phase 4: Smart contracts for Avalanche Fuji
- Phase 5: Backend–contract event integration
- Phase 6: React developer dashboard
- Phase 7: Reliability + error handling
- Phase 8: Full documentation + demo
- Phase 9: Additional verifiers and multi-agent consensus


## Commands

### Clone Repo