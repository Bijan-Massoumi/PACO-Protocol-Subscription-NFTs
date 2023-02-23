## A PaCo (Partial Common Ownership) NFT is a modified ERC-721 contract where every NFT is always on sale at a price set by its owner.

### What’s stopping someone from setting the price to a billion dollars?

The owner pays a SAF (Self Assessment Fee) proportionate to the price they’ve set. The percentage is at the discretion of the deployer. Because this fee scales with the price set, it creates an incentive to price the token close to how the owner truly values it.

If they want to hold onto the NFT, the owner can set a higher price (incurring a higher fee). If they want to flip it, they can set the price closer to the floor and pay less.

### How is the SAF collected?
The token owner posts a bond greater than or equal to a protocol-determined percentage of their self assessed price. Every block, a small amount of their bond drips out to pay their SAF. The percentage must be non-trivial to mitigate attack vectors explained later.

### Where do the collected protocol fees go?
An address can be set at deployment. Whether this address is a multi-sig, a DAO or the creator’s personal wallet is at the discretion of the deployer.

### Learn more

https://mirror.xyz/shah256.eth/GEnHL-CCQcCN0J9UYhR3WM4_4_dvWvvUmOmPG1ya64Q
