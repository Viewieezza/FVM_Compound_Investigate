# FVM_Compound_Investigate

## Setup

Deploy all necessary contract

1. Token.sol
2. myComptroller.sol
3. myCToken.sol (deploy 2 times)

Set CToken's constructure with Comptroller address from deployed myComptroller.sol.

```javascript
constructor(string memory name, string memory symbol, uint8 decimals, address underlying, address ComptrollerAddress, address CompAddr, uint256 initialExchangeRateMantissa) public{}
```

Next call function addToMarket() in Comptroller contract and inputs are 2 CToken address that we deployed.

```javascript
function addToMarket(address CTokenAddress) external returns(bool){}
```
## Problem

When trying to call function liquidityOf() in Comptroller contract, FVM showing reverted. 

But on ETH testnet, It's working well.

```javascript
function liquidityOf(address account) public override view returns(uint256){}
```
