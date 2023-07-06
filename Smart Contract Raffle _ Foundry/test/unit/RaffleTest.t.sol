// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {VRFCoordinatorV2Mock} from "../mocks/VRFCoordinatorV2Mock.sol";
import {CreateSubscription} from "../../script/Interactions.s.sol";



contract RaffleTest  is StdCheats, Test {
    
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed player);

    Raffle public raffle;
    HelperConfig public helperConfig;

        uint64 subscriptionId;
        bytes32 gasLane; // keyHash
        uint256 automationUpdateInterval;
        uint256 entryFee;
        uint32 callbackGasLimit;
        address vrfCoordinatorV2;    

    address public player1 = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() public {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();

        vm.deal(player1, STARTING_USER_BALANCE);

         (subscriptionId,
         gasLane, // keyHash
         automationUpdateInterval,
         entryFee,
         callbackGasLimit,
         vrfCoordinatorV2,
         ,
         ) = helperConfig.activeNetworkConfig();

         console.log("msg.sender :", msg.sender);
         console.log("block.chainid :", block.chainid);
         console.log("sub Id :", subscriptionId);
         console.log("vrfCoordinatorV2 :", vrfCoordinatorV2);
         /*console.log("link :", link);
         console.log("deployerKey :", deployerKey);*/
    }


    function testRaffleInitializesInOpenState() public view {

        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);

    }


    /////////////////////////
    //     enterRaffle     //
    /////////////////////////


    function testRaffleRevertsWhenFeeNotEnough() public {
        //Arrange
        vm.prank(player1);

        // Act // Assert
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerUponEntry() public {
        //Arrange
        vm.prank(player1);

        raffle.enterRaffle{value : 0.01 ether}();

        assert(raffle.getNumOfPlayers() == 1);      // 1 player entered
        assert(player1 == raffle.getPlayer(0));

    }

    function testRaffleEmitsEventOnEntry() public {

        vm.prank(player1);

        // https://book.getfoundry.sh/cheatcodes/expect-emit
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEnter(player1);                                           // expecting this emit on the next line
        raffle.enterRaffle{value : 0.01 ether}();

    }

    function testDontAllowEntryWhileRaffleIsCalculating() public { 

        vm.prank(player1);
        raffle.enterRaffle{value: 0.01 ether}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(player1);
        raffle.enterRaffle{value: 0.01 ether}();
    }  


      /////////////////////////
     //     checkUpkeep     //
    /////////////////////////  

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public { 

        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(upkeepNeeded == false);
        // same as
        // assert(!upKeepNeeded);
    }


    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
        
        vm.prank(player1);
        raffle.enterRaffle{value : 0.01 ether}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        Raffle.RaffleState raffleState = raffle.getRaffleState();

        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(!upKeepNeeded); // assert(upkeepNeeded == false);

    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {

        vm.prank(player1);
        raffle.enterRaffle{value : 0.01 ether}();

        
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upKeepNeeded); // assert(upkeepNeeded == false);

    }

    function testCheckUpkeepReturnsTrueIfConditionsSatisfied() public {

        vm.prank(player1);
        raffle.enterRaffle{value : 0.01 ether}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);
        
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        assert(upKeepNeeded == true); 

    }    

      /////////////////////////
     //   performUpkeep     //
    /////////////////////////  


    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public { 

        vm.prank(player1);
        raffle.enterRaffle{value : 0.01 ether}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);    

        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        assert(upKeepNeeded == true);
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public { 
    
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upKeepNeeded); // assert(upkeepNeeded == false); 

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState)
        );  
        raffle.performUpkeep("");

    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public {

        vm.prank(player1);
        raffle.enterRaffle{value : 0.01 ether}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1); 


        vm.recordLogs();
        raffle.performUpkeep("");   // emits event logs
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        
        assert(uint256(requestId) > 0);
        assert(uint(raffleState) == 1);         //  0 = open, 1 = calculating
    }


      /////////////////////////
     // fulfillRandomWords  //
    /////////////////////////  

    modifier raffleEntered() {
        vm.prank(player1);
        console.log("player1", player1);
        raffle.enterRaffle{value : 0.01 ether}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1); 

        _;
    }

    // only works on local test net
    modifier skipFork() {

        if(block.chainid != 31337) {
            return;
        }

        _;
    }


    /// FUZZ TEST ////   
        // Note : The following tests would NOT work in a mainnet or real testnet (like sepolia) 
        // coz , we're pretending to be the VRF using a mock contract here
        // the mock VRFCoordinatorV2Mock has different functionalities to the real VRFCordinatorV2 contract
        // thats why we use the skipFork modifier


    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 requestId) public raffleEntered skipFork {

        // during a fuzz test : foundry passes in 256 (default) diff numbers (for requestId) 
        // and checks if the test passes

        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(    
            requestId,                   
            address(raffle)
        );
    }



    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered skipFork {

        //  Arrange
        address expectedWinner = address(1);

        uint256 startingIndex = 1; // We have starting index be 1 so we can start with address(1) and not address(0)
        uint256 additionalEntrances = 4;

        for(uint256 i = startingIndex; i < startingIndex + additionalEntrances; i++) {

            address player = address(uint160(i));
            console.log("player address", player);
        // address player  = makeAddr("player", i);  
            hoax(player, 1 ether);
            raffle.enterRaffle{value : 0.01 ether}();
            console.log("Num of Players : ", raffle.getNumOfPlayers());
        }

        uint256 startTimestamp  = raffle.getLastTimeStamp();
        uint256 startingBalance = expectedWinner.balance;

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");   // emits requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];   // get the requestId from the logs


        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );


        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimestamp = raffle.getLastTimeStamp();
        uint256 prize = entryFee * (additionalEntrances + 1);    // +1 represents the raffleEntered modifier's player1 entry 
        


        assert(raffle.getNumOfPlayers() == 0);                    // players array is reset to 0
        assert(recentWinner == expectedWinner);
        assert(endingTimestamp > startTimestamp);
        assert(uint256(raffleState) == 0);
        assert(raffleState == Raffle.RaffleState.OPEN);
        assert(prize == 0.05 ether);
        assert(winnerBalance == startingBalance + prize);
        
    }        
}
