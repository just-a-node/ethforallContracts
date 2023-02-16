// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.17;
import "hardhat/console.sol";

import {IDestinationPool} from "../interfaces/IDestinationPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IConnext} from "@connext/smart-contracts/contracts/core/connext/interfaces/IConnext.sol";
 
import {IConstantFlowAgreementV1} from 
"@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import {
    ISuperfluid,
    ISuperToken,
    SuperAppDefinitions
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import {
    SuperAppBase
} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";

error Unauthorized();
error InvalidAgreement();
error InvalidToken();
error StreamAlreadyActive();

/// @title Origin Pool to Receive Streams.
/// @notice This is a super app. On stream (create|update|delete), this contract sends a message
/// accross the bridge to the DestinationPool.

contract OriginPool is SuperAppBase {

    /// @dev Emitted when flow message is sent across the bridge.
    /// @param flowRate Flow Rate, unadjusted to the pool.
    event FlowStartMessage(address indexed sender, address indexed receiver, int96 flowRate, uint256 startTime);
    event FlowTopupMessage(address indexed sender, address indexed receiver, int96 newFlowRate, uint256 topupTime, uint256 endTime);
    event FlowEndMessage(address indexed sender, address indexed receiver, int96 flowRate);

    enum StreamOptions {
        START,
        TOPUP,
        END
    }

    /// @dev Emitted when rebalance message is sent across the bridge.
    /// @param amount Amount rebalanced (sent).
    event RebalanceMessageSent(uint256 amount);

    /// @dev Nomad Domain of this contract. Goreli testnet
    uint32 public immutable originDomain = 1735353714;

    /// @dev Nomad Domain of the destination contract. Mumbai testnet
    uint32 public immutable destinationDomain = 9991;

    /// @dev Destination contract address
    address public destination;
    uint256 public cost = 1.0005003e18;
    // uint256 public relayerFeeCost = 0.10005003e18;

    /// @dev Connext contracts.
    IConnext public immutable connext = IConnext(0xFCa08024A6D4bCc87275b1E4A1E22B71fAD7f649);

    /// @dev Superfluid contracts.
    ISuperfluid public immutable host = ISuperfluid(0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9);
    IConstantFlowAgreementV1 public immutable cfa = IConstantFlowAgreementV1(0xEd6BcbF6907D4feEEe8a8875543249bEa9D308E8);
    ISuperToken public immutable token = ISuperToken(0x3427910EBBdABAD8e02823DFe05D34a65564b1a0); // TESTx token
    IERC20 public erc20Token = IERC20(0x7ea6eA49B0b0Ae9c5db7907d139D9Cd3439862a1); // TEST token


    /// @dev Validates callbacks.
    /// @param _agreementClass MUST be CFA.
    /// @param _token MUST be supported token.
    modifier isCallbackValid(address _agreementClass, ISuperToken _token) {
        if (msg.sender != address(host)) revert Unauthorized();
        if (_agreementClass != address(cfa)) revert InvalidAgreement();
        if (_token != token) revert InvalidToken();
        _;
    }

    constructor() {
        // surely this can't go wrong
        IERC20(token.getUnderlyingToken()).approve(address(connext), type(uint256).max);

        // register app
        host.registerApp(
            SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
        );
        console.log("Address performing the approval", msg.sender);
    }

    receive() payable external {}
    fallback() external payable {}

    // demoday hack. this is not permanent.
    bool done;
    error Done();
    function setDomain(address _destination) external {
        // if (done) revert Done();
        // done = true;
        destination = _destination;
    }

    // //////////////////////////////////////////////////////////////
    // REBALANCER
    // //////////////////////////////////////////////////////////////

    /// @dev Rebalances pools. This sends funds over the bridge to the destination.
    function rebalance() external {
        _sendRebalanceMessage();
    }

    function _sendFlowMessage(string memory streamActionType, address sender, address receiver,  int96 flowRate, uint256 relayerFee, uint256 slippage) external payable {
        uint256 buffer; 
        erc20Token.transferFrom(sender, address(this), cost); // here the account is my wallet account
        erc20Token.approve(address(connext), cost);
        // erc20Token.downgrade(buffer); 
        // encode call
        // bytes memory callData = abi.encodeCall(
        //     IDestinationPool(destination).receiveFlowMessage,
        //     (account, flowRate)
        // ); 

        bytes memory callData = abi.encode(streamActionType, sender, receiver, flowRate, block.timestamp);
        uint256 relayerFee = relayerFee; // 30000000000000000;
        uint256 slippage = slippage;
        connext.xcall{value: relayerFee}(
            destinationDomain,               // _destination: Domain ID of the destination chain
            destination,                     // _to: address receiving the funds on the destination
            address(erc20Token),      // _asset: address of the token contract
            msg.sender,                      // _delegate: address that can revert or forceLocal on destination
            cost,                         // _amount: amount of tokens to transfer
            slippage,                        // _slippage: the maximum amount of slippage the user will accept in BPS
            callData                         // _callData
        );
        emit FlowStartMessage(msg.sender, receiver, flowRate, block.timestamp);
    }

    // function callFlow(uint256 flowRate) external {
    //     _sendFlowMessage{value: 0.03 ether}(msg.sender, flowRate, 30000000000000000, 300);
    // }

    // //////////////////////////////////////////////////////////////
    // flow -> send lumpsum TEST to originPool -> bridge to destination -> upgrade to TESTx on destination -> stream
    // //////////////////////////////////////////////////////////////

    // //////////////////////////////////////////////////////////////
    // MESSAGE SENDERS
    // //////////////////////////////////////////////////////////////

    /// @dev Sends rebalance message with the full balance of this pool. No need to collect dust.
    function _sendRebalanceMessage() internal {
        uint256 balance = token.balanceOf(address(this));
        // downgrade for sending across the bridge
        token.downgrade(balance);
        // encode call
        bytes memory callData = abi.encodeWithSelector(
            IDestinationPool.receiveRebalanceMessage.selector
        );
        uint256 relayerFee = 0;
        uint256 slippage = 0;
        connext.xcall{value: relayerFee}(
            destinationDomain,               // _destination: Domain ID of the destination chain
            destination,                     // _to: address receiving the funds on the destination
            token.getUnderlyingToken(),      // _asset: address of the token contract
            address(this),                      // _delegate: address that can revert or forceLocal on destination
            balance,                         // _amount: amount of tokens to transfer
            slippage,                        // _slippage: the maximum amount of slippage the user will accept in BPS
            callData                         // _callData
        ); 
        emit RebalanceMessageSent(balance);
    }
 
    
}
