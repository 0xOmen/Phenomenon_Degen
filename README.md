# Phenomenon_Degen
Smart Contract repository for Phenomenon on the Degen L3

This is a complex contract written in Solidity, a language for writing smart contracts on Ethereum blockchain. The contract is named "Phenomenon" and it is a game where players (or "prophets") enter a game to try to survive and win. Here is a breakdown of what each part of the contract does:

1. The contract uses several imports to include OpenZeppelin's ERC20 token contract standard (IERC20) and its own ERC20 contract (ERC20). OpenZeppelin is a library for secure smart contract development.

2. Several custom errors are defined to handle specific error conditions in the contract. These errors are revert strings which can be triggered by the "revert" statement in a function. 

3. A contract "Phenomenon" is defined which includes several state variables to keep track of game state, player data, game parameters, etc. 

4. The contract includes several functions to manage game state, player registration, ticket buying/selling/claiming, etc. 

5. The contract includes several modifiers (like onlyOwner) to restrict function access based on conditions like ownership of a contract. 

6. The contract has a constructor which is called when a new contract instance is created (i.e., when a new game is started). It initializes several game parameters like interval between turns, entry fee, ticket multiplier, number of prophets allowed in a game, etc. 

7. Several events are emitted for logging purposes which can be tracked off-chain or in a smart contract subscribed to this event. 

8. The contract also includes several internal functions (starting with 'ruleCheck') for game logic like checking if a player is allowed to perform certain actions based on game state and player's turn. 

9. The contract includes a complex function (getPrice) for calculating ticket price based on supply and demand in a game. 

10. Finally, there are several external functions for managing game state like starting a game (startGame), changing game parameters like entry fee or ticket multiplier (changeEntryFee, changeTicketMultiplier), etc. 
