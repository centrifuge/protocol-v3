[![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry] [![Docs][docs-badge]][docs]

[gha]: https://github.com/centrifuge/protocol-v3/actions
[gha-badge]: https://github.com/centrifuge/protocol-v3/actions/workflows/ci.yml/badge.svg
[foundry]: https://getfoundry.sh
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[docs]: https://docs.centrifuge.io/developer/protocol/overview/
[docs-badge]: https://img.shields.io/badge/Docs-docs.centrifuge.io-6EDFFB.svg

# Centrifuge Protocol V3

Centrifuge V3 is an open, decentralized protocol for onchain asset management. Built on immutable smart contracts, it enables permissionless deployment of customizable tokenization products.

Build a wide range of use cases—from permissioned funds to onchain loans—while enabling fast, secure deployment. ERC-4626 and ERC-7540 vaults allow seamless integration into DeFi.

Using protocol-level chain abstraction, tokenization issuers access liquidity across any network, all managed from one Hub chain of their choice.

## Protocol

Centrifuge V3 operates on a hub-and-spoke model. Each pool chooses a single hub chain, and can tokenize and manage liquidity on many spoke chains.

### Centrifuge Hub
* Manage and control your tokens from a single chain of your choice
* Consolidate accounting of all your vaults in a single place
* Manage both RWAs & DeFi-native assets

### Centrifuge Spoke
* Tokenize ownership using ERC-20 — customizable with modules of your choice
* Distribute to DeFi with ERC-4626 and ERC-7540 vaults
* Support 1:1 token transfers between chains using burn-and-mint process

## Project structure
```
.
├── deployments
├── docs
│  └── audits
├── script
├── src
│  ├── misc
│  ├── common
│  ├── hub
│  ├── spoke
│  ├── vaults
│  └── hooks
├── test
├── foundry.toml
└── README.json
```
- `deployments` contains the deployment information of the supported chains
- `docs` documentation, diagrams and security audit reports
- `script` deployment scripts used to deploy a part or the full system, along with adapters.
- `src` main source containing all the contrats. Look for the interfaces and libraries inside of each module.
  - `misc` generic contracts
  - `common` common code to `hub` and `spoke`
  - `hub` code related to Centrifuge Hub
  - `spoke` code related to Centrifuge Spoke
  - `vaults` extension of Centrifuge Spoke, for ERC-4626 and ERC-7540 vaults
  - `hooks` extension of Centrifuge Spoke, for implementing transfer hooks
- `test` contains all tests: unitary test, integration test per module, and end-to-end integration tests


## Contributing
#### Getting started
```sh
git clone git@github.com:centrifuge/protocol-v3.git
cd protocol-v3
```

#### Testing
To build and run all tests locally:
```sh
forge test
```

## Audit reports

| Auditor                                              | Version            | Date            | Engagement                 | Report                                                                                                                                                                      |
| ---------------------------------------------------- | --------------- | --------------- | :------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Code4rena](https://code4rena.com/)                   | V1.0        | Sep 2023        | Competitive audit          | [`Report`](https://code4rena.com/reports/2023-09-centrifuge)                                                                                                                |
| [SRLabs](https://www.srlabs.de/)                     | V1.0        | Sep 2023        | Security review            | [`Report`](https://github.com/centrifuge/protocol-v3/blob/main/docs/audits/2023-09-SRLabs.pdf)                                                                              |
| [Cantina](https://cantina.xyz/)                      | V1.0        | Oct 2023        | Security review            | [`Report`](https://github.com/centrifuge/protocol-v3/blob/main/docs/audits/2023-10-Cantina.pdf)                                                                             |
| [Alex the Entreprenerd](https://x.com/gallodasballo) | V2.0        | Mar - Apr 2024  | Review + invariant testing | [`Part 1`](https://getrecon.substack.com/p/lessons-learned-from-fuzzing-centrifuge) [`Part 2`](https://getrecon.substack.com/p/lessons-learned-from-fuzzing-centrifuge-059) |
| [Spearbit](https://spearbit.com/)                    | V2.0        | July 2024       | Security review            | [`Report`](https://github.com/centrifuge/protocol-v3/blob/main/docs/audits/2024-08-Spearbit.pdf)                                                                            |
| [Recon](https://getrecon.xyz/) | V2.0        | Jan 2025  | Invariant testing | [`Report`](https://getrecon.substack.com/p/never-stop-improving-your-invariant) |
| [Cantina](https://cantina.xyz/)                      | V2.1        | Feb 2025        | Security review            | [`Report`](https://github.com/centrifuge/protocol-v3/blob/main/docs/audits/2025-02-Cantina.pdf)                                                                             |
| [xmxanuel](https://x.com/xmxanuel)                   | V3.0        | Mar 2025       | Security review            |  [`Report`](https://github.com/centrifuge/protocol-v3/blob/main/docs/audits/2025-03-xmxanuel.pdf)                                                                                                                                                                    |
| [burraSec](https://www.burrasec.com/)                      | V3.0        | Apr 2025        | Security review            | [`Part 1`](https://github.com/centrifuge/protocol-v3/blob/main/docs/audits/2025-04-burraSec-1.pdf) [`Part 2`](https://github.com/centrifuge/protocol-v3/blob/main/docs/audits/2025-04-burraSec-2.pdf)                                                                             |
| [Alex the Entreprenerd](https://x.com/gallodasballo)                     | V3.0        | Apr 2025        | Review + invariant testing            | [`Report`](https://github.com/Recon-Fuzz/audits/blob/main/Centrifuge_Protocol_V3.MD)                                                                             |
| [xmxanuel](https://x.com/xmxanuel)                   | V3.0        | May 2025       | Security review            |  [`Report`](https://github.com/centrifuge/protocol-v3/blob/main/docs/audits/2025-05-xmxanuel.pdf)                                                                                                                                                                    |
| [burraSec](https://www.burrasec.com/)                      | V3.0        | May 2025        | Security review            | [`Report`](https://github.com/centrifuge/protocol-v3/blob/main/docs/audits/2025-05-burraSec.pdf)                                                                             |
| [Cantina](https://cantina.xyz/)                      | V3.0        | May 2025        | Security review            | [`Report`](https://github.com/centrifuge/protocol-v3/blob/main/docs/audits/2025-05-Cantina.pdf)                                                                             |
| [Macro](https://0xmacro.com/)                      | V3.0        | May 2025        | Security review            | [`Report`](https://0xmacro.com/library/audits/centrifuge-1.html)                                                                             |

## License
The primary license is the [Business Source License 1.1](https://github.com/centrifuge/protocol-v3/blob/main/LICENSE). However, all files in the [`src/misc`](./src/misc) folder, [`src/managers/MerkleProofManager.sol`](./src/managers/MerkleProofManager.sol), and any interface file can also be licensed under `GPL-2.0-or-later` (as indicated in their SPDX headers).
