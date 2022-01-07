# Brahma Vaults

Core smart contracts for vaults @ [brahma.fi](https://brahma.fi/).

## Repo Guide

### Setup

- Clone the repo using

  ```
  git clone https://github.com/Brahma-fi/brahma-vaults.git --recursive
  ```

  (OR)

  ```
  git clone https://github.com/Brahma-fi/brahma-vaults.git
  git submodule update --init --recursive
  ```

- To install new dependencies
  ```
  forge install <github-username>/<repository>
  ```
- To update dependencies
  - If master
    ```
    forge update
    ```
  - If from specific branch
    ```
    git submodule foreach git pull <branch>
    ```

### Environment

```
 export ETH_RPC_URL=<rpc-url>
 export ETHERSCAN_API_KEY=<etherscan-api-key>
 export ETH_RPC_ACCOUNTS=yes
 export ETH_KEYSTORE=<keystore>
 export ETH_FROM=<eth-address>
```

### Operations

- Build

```
make all
```

- Test

```
make test
```

(requires ETH_RPC_URL set)

- Deploy

```
forge build <path-to-contract> --constructor-args <constructor-args-space-separated> --private-key <eth-private-key>
```
