// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

error Game__NotOpen();
error Game__Full();
error Game__AlreadyRegistered();
error Game__ProphetNumberError();
error Game__NotInProgress();
error Game__ProphetIsDead();
error Game__NotAllowed();
error Game__NotEnoughTicketsOwned();
error Game__AddressIsEliminated();
error Game__ProphetNotFree();
error Game__OutOfTurn();
error Contract__OnlyOwner();
error Game__NoRandomNumber();

contract Phenomenon {
    /////////////////////////////Game Variables///////////////////////////////////
    enum GameState {
        OPEN,
        IN_PROGRESS,
        PAUSED,
        ENDED
    }

    struct ProphetData {
        address playerAddress;
        bool isAlive;
        bool isFree;
        uint256 args;
    }

    //Set interval to 3 minutes = 180
    uint256 immutable INTERVAL;
    uint256 ENTRANCE_FEE;
    uint256 ticketMultiplier;
    uint16 public NUMBER_OF_PROPHETS;
    address GAME_TOKEN;
    uint256 public s_gameNumber;
    address owner;

    //Tracks tokens deposited each game, resets every game
    uint256 public tokenBalance;
    uint256 ownerTokenBalance;
    uint256 lastRoundTimestamp;
    //mapping of addresses that have signed up to play by game: prophetList[s_gameNumber][address]
    //returns 0 if not signed up and 1 if has signed up
    mapping(uint256 => mapping(address => bool)) public prophetList;
    ProphetData[] public prophets;
    GameState public gameStatus;
    uint256 public prophetsRemaining;
    uint256 roleVRFSeed;
    uint256 gameRound;
    mapping(uint256 => uint256) public currentProphetTurn;

    // mapping of which prophet each address holds allegiance tickets to
    mapping(uint256 => mapping(address => uint256)) public allegiance;
    // mapping of how many tickets an address owns
    mapping(uint256 => mapping(address => uint256)) public ticketsToValhalla;
    // mapping of how ticket value by game
    mapping(uint256 => uint256) public tokensPerTicket;
    uint256 encryptor;
    //tracks how many tickets to heaven have been sold for each Prophet
    uint256[] public accolites;
    uint256[] public highPriestsByProphet;
    uint256 public totalTickets;

    event prophetEnteredGame(
        uint256 indexed prophetNumber,
        address indexed sender,
        uint256 indexed gameNumber
    );
    event gameStarted(uint256 indexed gameNumber);
    event miracleAttempted(
        bool indexed isSuccess,
        uint256 indexed currentProphetTurn
    );
    event smiteAttempted(
        uint256 indexed target,
        bool indexed isSuccess,
        uint256 indexed currentProphetTurn
    );
    event accusation(
        bool indexed isSuccess,
        bool targetIsAlive,
        uint256 indexed currentProphetTurn,
        uint256 indexed _target
    );
    event gameEnded(
        uint256 indexed gameNumber,
        uint256 indexed tokensPerTicket,
        uint256 indexed currentProphetTurn
    );
    event gameReset(uint256 indexed newGameNumber);
    event religionLost(
        uint256 indexed _target,
        uint256 indexed numTicketsSold,
        uint256 indexed totalPrice,
        address sender
    );
    event gainReligion(
        uint256 indexed _target,
        uint256 indexed numTicketsBought,
        uint256 indexed totalPrice,
        address sender
    );
    event ticketsClaimed(
        uint256 indexed ticketsClaimed,
        uint256 indexed tokensSent,
        uint256 indexed gameNumber
    );
    event currentTurn(uint256 indexed nextProphetTurn);

    constructor(
        uint256 _interval, //180
        uint256 _entranceFee, //10000000000000000000000  (10,000)
        uint256 _ticketMultiplier, // 1000
        uint16 _numProphets,
        address _gameToken //0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed $DEGEN
    ) {
        owner = msg.sender;
        INTERVAL = _interval;
        ENTRANCE_FEE = _entranceFee;
        ticketMultiplier = _ticketMultiplier;
        NUMBER_OF_PROPHETS = _numProphets;
        encryptor = 8;
        s_gameNumber = 0;
        gameStatus = GameState.OPEN;
        lastRoundTimestamp = block.timestamp;
        gameRound = 0;

        GAME_TOKEN = _gameToken;
        tokenBalance = 0;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function changeOwner(address newOwner) public onlyOwner {
        owner = newOwner;
    }

    function ownerChangeGameState(GameState _status) public onlyOwner {
        gameStatus = _status;
    }

    function changeEntryFee(uint256 newFee) public onlyOwner {
        ENTRANCE_FEE = newFee;
    }

    function changeTicketMultiplier(uint256 newMultiplier) public onlyOwner {
        ticketMultiplier = newMultiplier;
    }

    function enterGame() public {
        if (gameStatus != GameState.OPEN) {
            revert Game__NotOpen();
        }
        if (prophets.length >= NUMBER_OF_PROPHETS) {
            revert Game__Full();
        }
        if (prophetList[s_gameNumber][msg.sender]) {
            revert Game__AlreadyRegistered();
        }
        ProphetData memory newProphet;
        newProphet.playerAddress = msg.sender;
        newProphet.isAlive = true;
        newProphet.isFree = true;
        prophets.push(newProphet);
        tokenBalance += ENTRANCE_FEE;
        prophetList[s_gameNumber][msg.sender] = true;
        prophetsRemaining++;

        emit prophetEnteredGame(
            prophetsRemaining - 1,
            msg.sender,
            s_gameNumber
        );

        if (prophetsRemaining == NUMBER_OF_PROPHETS) {
            startGame();
        }

        IERC20(GAME_TOKEN).transferFrom(
            msg.sender,
            address(this),
            ENTRANCE_FEE
        );
    }

    function startGame() public {
        if (gameStatus != GameState.OPEN) {
            revert Game__NotOpen();
        }
        if (prophets.length != NUMBER_OF_PROPHETS) {
            revert Game__ProphetNumberError();
        }

        ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        roleVRFSeed = uint256(blockhash(block.number - 1));

        currentProphetTurn[s_gameNumber] = block.timestamp % NUMBER_OF_PROPHETS;
        for (uint _prophet = 0; _prophet < NUMBER_OF_PROPHETS; _prophet++) {
            if (
                currentProphetTurn[s_gameNumber] ==
                (roleVRFSeed / (42069420690990990091337 * encryptor)) %
                    NUMBER_OF_PROPHETS ||
                ((uint256(blockhash(block.number - 1 - _prophet))) % 100) >= 25
            ) {
                // assign allegiance to self
                allegiance[s_gameNumber][
                    prophets[_prophet].playerAddress
                ] = _prophet;
                // give Prophet one of his own tickets
                ticketsToValhalla[s_gameNumber][
                    prophets[_prophet].playerAddress
                ] = 1;
                // Increment total tickets by 1
                totalTickets++;
                // This loop initializes accolites[]
                // each loop pushes the number of accolites/tickets sold into the prophet slot of the array
                highPriestsByProphet.push(1);
            } else {
                highPriestsByProphet.push(0);
                prophetsRemaining--;
                prophets[_prophet].isAlive = false;
                prophets[_prophet].args = 99;
            }
            accolites.push(0);
        }
        turnManager();
        gameStatus = GameState.IN_PROGRESS;
        emit gameStarted(s_gameNumber);
    }

    function ruleCheck() internal view {
        // Game must be in progress
        if (gameStatus != GameState.IN_PROGRESS) {
            revert Game__NotInProgress();
        }
        // Sending address must be their turn
        if (
            msg.sender !=
            prophets[currentProphetTurn[s_gameNumber]].playerAddress
        ) {
            revert Game__OutOfTurn();
        }
    }

    function performMiracle() public {
        // If turn time interval has passed then anyone can call performMiracle on current Prophet's turn
        if (block.timestamp < lastRoundTimestamp + INTERVAL) {
            ruleCheck();
        }

        if (
            currentProphetTurn[s_gameNumber] ==
            (roleVRFSeed / (42069420690990990091337 * encryptor)) %
                NUMBER_OF_PROPHETS ||
            ((block.timestamp) % 100) +
                (getTicketShare(currentProphetTurn[s_gameNumber]) / 10) >=
            25
        ) {
            if (prophets[currentProphetTurn[s_gameNumber]].isFree == false) {
                prophets[currentProphetTurn[s_gameNumber]].isFree = true;
            }
        } else {
            // kill prophet
            prophets[currentProphetTurn[s_gameNumber]].isAlive = false;
            // Remove Prophet's accolite tickets from totalTickets for TicketShare calc
            totalTickets -= (accolites[currentProphetTurn[s_gameNumber]] -
                highPriestsByProphet[currentProphetTurn[s_gameNumber]]);
            // decrease number of remaining prophets
            prophetsRemaining--;
        }
        emit miracleAttempted(
            prophets[currentProphetTurn[s_gameNumber]].isAlive,
            currentProphetTurn[s_gameNumber]
        );
        turnManager();
    }

    // game needs to be playing, prophet must be alive
    function attemptSmite(uint256 _target) public {
        ruleCheck();
        // Prophet to smite must be alive and exist
        if (
            _target >= NUMBER_OF_PROPHETS || prophets[_target].isAlive == false
        ) {
            revert Game__NotAllowed();
        }

        prophets[currentProphetTurn[s_gameNumber]].args = _target;
        if (
            currentProphetTurn[s_gameNumber] ==
            (roleVRFSeed / (42069420690990990091337 * encryptor)) %
                NUMBER_OF_PROPHETS ||
            1 +
                (uint256(block.timestamp % 100) +
                    (getTicketShare(currentProphetTurn[s_gameNumber]) / 2)) >=
            90
        ) {
            // kill prophet
            prophets[_target].isAlive = false;
            // Remove Prophet's accolite tickets from totalTickets for TicketShare calc
            totalTickets -= (accolites[_target] +
                highPriestsByProphet[_target]);
            // decrease number of remaining prophets
            prophetsRemaining--;
        } else {
            if (prophets[currentProphetTurn[s_gameNumber]].isFree == true) {
                prophets[currentProphetTurn[s_gameNumber]].isFree = false;
            } else {
                prophets[currentProphetTurn[s_gameNumber]].isAlive = false;
                // Remove Prophet's accolite tickets from totalTickets for TicketShare calc
                totalTickets -= (accolites[currentProphetTurn[s_gameNumber]] +
                    highPriestsByProphet[currentProphetTurn[s_gameNumber]]);
                // decrease number of remaining prophets
                prophetsRemaining--;
            }
        }
        emit smiteAttempted(
            _target,
            !prophets[_target].isAlive,
            currentProphetTurn[s_gameNumber]
        );
        turnManager();
    }

    function accuseOfBlasphemy(uint256 _target) public {
        ruleCheck();
        // Prophet to accuse must be alive and exist
        if (
            _target >= NUMBER_OF_PROPHETS || prophets[_target].isAlive == false
        ) {
            revert Game__NotAllowed();
        }
        // Message Sender must be living & free prophet on their turn
        if (prophets[currentProphetTurn[s_gameNumber]].isFree == false) {
            revert Game__ProphetNotFree();
        }
        prophets[currentProphetTurn[s_gameNumber]].args = _target;

        if (
            1 +
                (uint256(
                    (block.timestamp * currentProphetTurn[s_gameNumber]) % 100
                ) + getTicketShare(currentProphetTurn[s_gameNumber])) >
            90
        ) {
            if (prophets[_target].isFree == true) {
                prophets[_target].isFree = false;
                emit accusation(
                    true,
                    true,
                    currentProphetTurn[s_gameNumber],
                    _target
                );
            } else {
                // kill prophet
                prophets[_target].isAlive = false;
                // Remove Prophet's accolite tickets from totalTickets for TicketShare calc
                totalTickets -= (accolites[_target] +
                    highPriestsByProphet[_target]);
                // decrease number of remaining prophets
                prophetsRemaining--;
                emit accusation(
                    true,
                    false,
                    currentProphetTurn[s_gameNumber],
                    _target
                );
            }
        } else {
            // set target free
            prophets[_target].isFree = true;
            // put failed accuser in jail
            prophets[currentProphetTurn[s_gameNumber]].isFree = false;
            emit accusation(
                false,
                true,
                currentProphetTurn[s_gameNumber],
                _target
            );
        }
        turnManager();
    }

    // Allow NUMBER_OF_PROPHETS to be changed in Hackathon but maybe don't let this happen in Production?
    // There may be a griefing vector I haven't thought of
    function reset(uint16 _numberOfPlayers) public {
        if (msg.sender != owner) {
            if (gameStatus != GameState.ENDED) {
                revert Game__NotInProgress();
            }
            if (block.timestamp < lastRoundTimestamp + 30) {
                revert Game__NotAllowed();
            }
            if (_numberOfPlayers < 4 || _numberOfPlayers > 9) {
                revert Game__ProphetNumberError();
            }
        }

        s_gameNumber++;
        tokenBalance = 0;
        delete prophets; //array of structs
        gameStatus = GameState.OPEN;
        prophetsRemaining = 0;
        gameRound = 0;
        NUMBER_OF_PROPHETS = _numberOfPlayers;

        delete accolites; //array
        delete highPriestsByProphet; //array
        totalTickets = 0;
        emit gameReset(s_gameNumber);
    }

    function turnManager() internal {
        bool stillFinding = true;
        if (prophetsRemaining == 1) {
            gameStatus = GameState.ENDED;
            if (prophets[currentProphetTurn[s_gameNumber]].isAlive) {
                stillFinding = false;
            }

            uint256 winningTokenCount = accolites[
                currentProphetTurn[s_gameNumber]
            ] + highPriestsByProphet[currentProphetTurn[s_gameNumber]];
            if (winningTokenCount != 0) {
                ownerTokenBalance += (tokenBalance * 5) / 100;
                tokenBalance = (tokenBalance * 95) / 100;
                tokensPerTicket[s_gameNumber] =
                    tokenBalance /
                    winningTokenCount;
            } else {
                tokensPerTicket[s_gameNumber] = 0;
                ownerTokenBalance += tokenBalance;
            }
        }

        uint256 nextProphetTurn = currentProphetTurn[s_gameNumber] + 1;
        while (stillFinding) {
            if (nextProphetTurn >= NUMBER_OF_PROPHETS) {
                nextProphetTurn = 0;
            }
            if (prophets[nextProphetTurn].isAlive) {
                currentProphetTurn[s_gameNumber] = nextProphetTurn;
                gameRound++;
                lastRoundTimestamp = block.timestamp;
                stillFinding = false;
            }
            nextProphetTurn++;
        }
        emit currentTurn(currentProphetTurn[s_gameNumber]);
        if (prophetsRemaining == 1) {
            emit gameEnded(
                s_gameNumber,
                tokensPerTicket[s_gameNumber],
                currentProphetTurn[s_gameNumber]
            );
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////
    //////////// TICKET FUNCTIONS //////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////
    function getTicketShare(uint256 _playerNum) public view returns (uint256) {
        if (totalTickets == 0) return 0;
        else
            return
                ((accolites[_playerNum] + highPriestsByProphet[_playerNum]) *
                    100) / totalTickets;
    }

    function highPriest(uint256 _senderProphetNum, uint256 _target) public {
        // Only prophets can call this function
        // Prophet must be alive or assigned to high priest
        // Can't try to follow non-existent prophet
        // Can't call if <= 2 prophets remain
        if (
            prophets[_senderProphetNum].playerAddress != msg.sender ||
            (!prophets[_senderProphetNum].isAlive &&
                prophets[_senderProphetNum].args != 99) ||
            _target >= NUMBER_OF_PROPHETS ||
            prophetsRemaining <= 2
        ) {
            revert Game__NotAllowed();
        }
        // Can't change allegiance if following an eliminated prophet
        if (prophets[allegiance[s_gameNumber][msg.sender]].isAlive == false) {
            if (
                allegiance[s_gameNumber][msg.sender] == 0 &&
                prophets[0].args != 99
            ) revert Game__AddressIsEliminated();
        }
        if (gameStatus != GameState.IN_PROGRESS) {
            revert Game__NotInProgress();
        }
        if (ticketsToValhalla[s_gameNumber][msg.sender] > 0) {
            highPriestsByProphet[allegiance[s_gameNumber][msg.sender]]--;
            ticketsToValhalla[s_gameNumber][msg.sender]--;
            totalTickets--;
            emit religionLost(_target, 1, 0, msg.sender);
        }
        emit gainReligion(_target, 1, 0, msg.sender);
        highPriestsByProphet[_target]++;
        ticketsToValhalla[s_gameNumber][msg.sender]++;
        allegiance[s_gameNumber][msg.sender] = _target;
        totalTickets++;
    }

    function getPrice(
        uint256 supply,
        uint256 amount
    ) public view returns (uint256) {
        uint256 sum1 = supply == 0
            ? 0
            : ((supply) * (1 + supply) * (2 * (supply) + 1)) / 6;
        uint256 sum2 = (((1 + supply) + amount - 1) *
            ((1 + supply) + amount) *
            (2 * ((1 + supply) + amount - 1) + 1)) / 6;
        uint256 summation = sum2 - sum1;
        return (((summation * 1 ether) * ticketMultiplier) / 2);
    }

    function getReligion(uint256 _prophetNum, uint256 _ticketsToBuy) public {
        // Make sure game state allows for tickets to be bought
        if (gameStatus != GameState.IN_PROGRESS) {
            revert Game__NotInProgress();
        }
        // Prophets cannot buy tickets
        // the ability to send 'buy' 0 tickets allows changing of allegiance
        if (prophetList[s_gameNumber][msg.sender] || _ticketsToBuy == 0) {
            revert Game__NotAllowed();
        }
        // Can't buy tickets of dead or nonexistent prophets
        if (
            prophets[_prophetNum].isAlive == false ||
            _prophetNum >= NUMBER_OF_PROPHETS
        ) {
            revert Game__ProphetIsDead();
        }
        /*
        // Cannot buy/sell  tickets if address eliminated (allegiant to prophet when killed)
        // Addresses that own no tickets will default allegiance to 0 but 0 is a player number
        //  This causes issues with game logic so if allegiance is to 0
        //  we must also check if sending address owns tickets
        // If the address owns tickets then they truly have allegiance to player 0
        if (
            prophets[allegiance[s_gameNumber][msg.sender]].isAlive == false &&
            ticketsToValhalla[s_gameNumber][msg.sender] != 0
        ) {
            revert Game__AddressIsEliminated();
        }

        // Check if player owns any tickets of another prophet
        if (
            ticketsToValhalla[s_gameNumber][msg.sender] != 0 &&
            allegiance[s_gameNumber][msg.sender] != _prophetNum
        ) {
            revert Game__NotAllowed();
        } */

        uint256 totalPrice = getPrice(accolites[_prophetNum], _ticketsToBuy);

        ticketsToValhalla[s_gameNumber][msg.sender] += _ticketsToBuy;
        accolites[_prophetNum] += _ticketsToBuy;
        totalTickets += _ticketsToBuy;
        tokenBalance += totalPrice;
        allegiance[s_gameNumber][msg.sender] = _prophetNum;
        emit gainReligion(_prophetNum, _ticketsToBuy, totalPrice, msg.sender);

        IERC20(GAME_TOKEN).transferFrom(msg.sender, address(this), totalPrice);
    }

    /*
    function loseReligion(uint256 _ticketsToSell) public {
        if (gameStatus != GameState.IN_PROGRESS) {
            revert Game__NotInProgress();
        }
        // Can't sell tickets of a dead prophet
        if (prophets[allegiance[s_gameNumber][msg.sender]].isAlive == false) {
            revert Game__ProphetIsDead();
        }
        // Prophets cannot sell tickets
        if (prophetList[s_gameNumber][msg.sender]) {
            revert Game__NotAllowed();
        }
        if (
            _ticketsToSell <= ticketsToValhalla[s_gameNumber][msg.sender] &&
            _ticketsToSell != 0
        ) {
            // Get price of selling tickets
            uint256 totalPrice = getPrice(
                accolites[allegiance[s_gameNumber][msg.sender]] -
                    _ticketsToSell,
                _ticketsToSell
            );
            emit religionLost(
                allegiance[s_gameNumber][msg.sender],
                _ticketsToSell,
                totalPrice,
                msg.sender
            );
            // Reduce the total number of tickets sold in the game by number of tickets sold by msg.sender
            totalTickets -= _ticketsToSell;
            accolites[allegiance[s_gameNumber][msg.sender]] -= _ticketsToSell;
            // Remove tickets from msg.sender's balance
            ticketsToValhalla[s_gameNumber][msg.sender] -= _ticketsToSell;
            // If msg.sender sold all tickets then set allegiance to 0
            if (ticketsToValhalla[s_gameNumber][msg.sender] == 0)
                allegiance[s_gameNumber][msg.sender] = 0;
            // Subtract the price of tickets sold from the tokenBalance for this game
            tokenBalance -= totalPrice;
            //Take 5% fee
            ownerTokenBalance += (totalPrice * 5) / 100;
            totalPrice = (totalPrice * 95) / 100;

            IERC20(GAME_TOKEN).transfer(msg.sender, totalPrice);
        } else revert Game__NotEnoughTicketsOwned();
    }*/

    function claimTickets(uint256 _gameNumber) public {
        if (_gameNumber >= s_gameNumber) {
            revert Game__NotAllowed();
        }
        // TurnManager sets currentProphetTurn to game winner, so use this to check if allegiance is to the winner
        if (
            allegiance[_gameNumber][msg.sender] !=
            currentProphetTurn[_gameNumber]
        ) {
            revert Game__AddressIsEliminated();
        }
        if (ticketsToValhalla[_gameNumber][msg.sender] == 0) {
            revert Game__NotEnoughTicketsOwned();
        }

        uint256 tokensToSend = ticketsToValhalla[_gameNumber][msg.sender] *
            tokensPerTicket[_gameNumber];
        ticketsToValhalla[_gameNumber][msg.sender] = 0;

        emit ticketsClaimed(
            ticketsToValhalla[_gameNumber][msg.sender],
            tokensToSend,
            _gameNumber
        );

        IERC20(GAME_TOKEN).transfer(msg.sender, tokensToSend);
    }

    function getOwnerTokenBalance() public view returns (uint256) {
        return ownerTokenBalance;
    }

    function ownerTokenTransfer(
        uint256 _amount,
        address _token,
        address _destination
    ) public onlyOwner {
        IERC20(_token).transfer(_destination, _amount);
    }
}
