// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;
// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

/*
import {VRFConsumerBaseV2} from "../lib/chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from  "../lib/chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {AutomationCompatibleInterface} from "../lib/chainlink/contracts/src/v0.8/interfaces/automation/AutomationCompatibleInterface.sol";
*/
import {VRFConsumerBaseV2} from "chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from  "chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {AutomationCompatibleInterface} from "chainlink/contracts/src/v0.8/interfaces/automation/AutomationCompatibleInterface.sol";


contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
    
/* Error */

error Raffle__TransferFailed();
error Raffle__SendMoreToEnterRaffle();
error Raffle__RaffleNotOpen();
error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

/* Type declarations */
enum RaffleState {
    OPEN,
    CALCULATING
}


/* State variables */
// Chainlink VRF Variables

VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
uint64 private immutable i_subscriptionId;
bytes32 private immutable i_gasLane;                // keyHash
uint32 private immutable i_callbackGasLimit;
uint16 private constant REQUEST_CONFIRMATIONS = 3;
uint32 private constant NUM_WORDS = 1;   


// Lottery Variables
    
uint256 public immutable i_entryFee;
uint256 private immutable i_interval;
uint256 private s_lastTimeStamp;
address private s_recentWinner;

address payable[] private s_players;
RaffleState private s_raffleState;



event RaffleEnter(address indexed player);
event RequestedRaffleWinner(uint256 indexed requestId);
event WinnerPicked(address indexed player);

// flexible constructor initialization depending on the chain id where it is deployed 
// refer DeployRaffle & HelperConfig scripts

    constructor(
        uint256 entryFee,
        uint256 interval,
        address vrfCoordinatorV2,
        uint64 subscriptionId,
        bytes32 gasLane, // keyHash
        uint32 callbackGasLimit  
        ) VRFConsumerBaseV2(vrfCoordinatorV2)  {
        
        i_entryFee = entryFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_subscriptionId = subscriptionId;
        i_gasLane = gasLane;
        i_callbackGasLimit = callbackGasLimit;        
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        }


    function enterRaffle() public payable {
        if(msg.value < i_entryFee) 
            revert Raffle__SendMoreToEnterRaffle();

        if(s_raffleState != RaffleState.OPEN) 
            revert Raffle__RaffleNotOpen();

        // Named events with the function name reversed
        s_players.push(payable(msg.sender));


        emit RaffleEnter(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink Automation nodes call every block
     * they look for `upkeepNeeded` to return True.
     * 
     * the following should be true for this to return true:
     * 1. The time interval has passed between raffle runs.
     * 2. The lottery is open.
     * 3. The contract has ETH.
     * 4. Implicity, your subscription is funded with LINK.
     */

    function checkUpkeep(bytes memory /* checkData */) public view override returns (bool upkeepNeeded, bytes memory /* performData */) {

        bool timePassed = (block.timestamp > (s_lastTimeStamp + i_interval));
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0 ;

        upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);

        return (upkeepNeeded, "0x0"); // can we comment this out? 

    }

    /**
     * @dev Once `checkUpkeep` is returning `true`, this function is called
     * and it kicks off a Chainlink VRF call to get a random winner.
     */


    function performUpkeep(bytes calldata /*performData*/) external override {
        
        // Best practices : Revalidate performUpkeep on Automation-compatible contracts , since this function is external

        (bool upkeepNeeded, ) = checkUpkeep("");
        
        if(!upkeepNeeded){
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;

        uint256 requestId = i_vrfCoordinator.requestRandomWords(
						        i_gasLane,
						        i_subscriptionId,
						        REQUEST_CONFIRMATIONS,
						        i_callbackGasLimit,
						        NUM_WORDS
							    );
        
        emit RequestedRaffleWinner(requestId);
        
    }
    /**
     * @dev This is the function that Chainlink VRF node
     * calls to send the random number (winner)
     */

    function fulfillRandomWords(uint256 /*requestId*/, uint256[] memory randomWords) internal override {

        uint winnerIndex = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[winnerIndex];
        s_recentWinner = recentWinner;

        // reset state variables
        s_players = new address payable[](0);
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;

        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        
        if(!success) 
            revert Raffle__TransferFailed();

        emit WinnerPicked(recentWinner);

    }


    /* Getter Functions */ 

    // Note: REQUEST_CONFIRMATIONS and NUM_WORDS are marked as pure 
    // since they are constants and do not rely on any contract state.

    function getRequestConfirmations() public pure returns (uint16) {
         return REQUEST_CONFIRMATIONS;
    }

    function getNumWords() public pure returns (uint32) {
         return NUM_WORDS;
    }

    function getEntryFee() public view returns (uint256) {
        return i_entryFee;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }

    function getLastTimeStamp() public view returns (uint256) {
         return s_lastTimeStamp;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getNumOfPlayers() public view returns (uint256) {
        return s_players.length;
    }

    function getPlayer(uint256 index) public view returns(address) {
        return s_players[index];
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

}   
