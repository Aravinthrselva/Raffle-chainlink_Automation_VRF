// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Raffle} from "../src/Raffle.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";




contract DeployRaffle is Script {

    function run() external returns(Raffle, HelperConfig) {

    // Deploying an instance of HelperConfig -- This comes with our mocks    
    HelperConfig helperConfig = new HelperConfig();    
        (   
            uint64 subscriptionId,
            bytes32 gasLane,
            uint256 automationUpdateInterval,
            uint256 entryFee,
            uint32 callbackGasLimit,
            address vrfCoordinatorV2,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();   

    // If a subscriptionId isnt already created, 
    // we have to programmatically create a new Subscription, 
    // and add funds (LINK tokens) to it

    if(subscriptionId == 0) {
        CreateSubscription createSubInstance = new CreateSubscription();
        subscriptionId = createSubInstance.createSubscription(vrfCoordinatorV2, deployerKey);
        

        FundSubscription fundSubInstance = new FundSubscription();
        fundSubInstance.fundSubscription(vrfCoordinatorV2, subscriptionId, link, deployerKey);

    }

    //Deploying the Raffle contract 

    vm.startBroadcast(deployerKey);
    Raffle raffle = new Raffle(
        entryFee,
        automationUpdateInterval,
        vrfCoordinatorV2,
        subscriptionId,
        gasLane,
        callbackGasLimit
    );
    vm.stopBroadcast();

    AddConsumer addConsumerInstance = new AddConsumer();

    //Adding our latest Raffle contract to the consumer list of our subscription
    addConsumerInstance.addConsumer(subscriptionId, vrfCoordinatorV2, deployerKey, address(raffle));
    
    console.log("address(raffle) :", address(raffle));
    console.log("msg.sender:", msg.sender);

    return(raffle, helperConfig);
    }
}
