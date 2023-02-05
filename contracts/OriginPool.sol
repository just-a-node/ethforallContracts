// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.17;

import {IDestinationPool} from "../interfaces/IDestinationPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IConnext} from "@connext/nxtp-contracts/contracts/core/connext/interfaces/IConnext.sol";

import {IConstantFlowAgreementV1} from 
"@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import {
    ISuperfluid,
    ISuperToken,
    SuperAppDefinitions
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

error Unauthorized();
error InvalidAgreement();
error InvalidToken();
error StreamAlreadyActive();

/// @title Origin Pool to Receive Streams.
/// @notice This is a super app. On stream (create|update|delete), this contract sends a message
/// accross the bridge to the DestinationPool.

contract OriginPool {

    /// @dev Emitted when flow message is sent across the bridge.
    /// @param account Streamer account (only one-to-one address streaming for now).
    /// @param flowRate Flow Rate, unadjusted to the pool.
    event FlowMessageSent(
        address indexed account,
        int96 flowRate
    );

    /// @dev Emitted when rebalance message is sent across the bridge.
    /// @param amount Amount rebalanced (sent).
    event RebalanceMessageSent(uint256 amount);

    /// @dev Nomad Domain of this contract.
    uint32 public immutable originDomain = 1735353714;

    /// @dev Nomad Domain of the destination contract.
    uint32 public immutable destinationDomain = 9991;

    /// @dev Destination contract address
    address public destination;

    /// @dev Connext contracts.
    IConnext public immutable connext = IConnext(0xFCa08024A6D4bCc87275b1E4A1E22B71fAD7f649);

    /// @dev Superfluid contracts.
    ISuperfluid public immutable host = ISuperfluid(0x22ff293e14F1EC3A09B137e9e06084AFd63adDF9);
    IConstantFlowAgreementV1 public immutable cfa = IConstantFlowAgreementV1(0xEd6BcbF6907D4feEEe8a8875543249bEa9D308E8);
    ISuperToken public immutable token = ISuperToken(0x9D4aD766C0ef90829d04A6B142196E53D642F631);

    /// @dev Validates callbacks.
    /// @param _agreementClass MUST be CFA.
    /// @param _token MUST be supported token.
    modifier isCallbackValid(address _agreementClass, ISuperToken _token) {
        if (msg.sender != address(host)) revert Unauthorized();
        if (_agreementClass != address(cfa)) revert InvalidAgreement();
        if (_token != token) revert InvalidToken();
        _;
    }

    // constructor(
    //     // uint32 _originDomain,
    //     // uint32 _destinationDomain,
    //     // // address _destination,
    //     // IConnext _connext,
    //     // ISuperfluid _host,
    //     // IConstantFlowAgreementV1 _cfa,
    //     // ISuperToken _token
    // ) {
    //     // originDomain = _originDomain;
    //     // destinationDomain = _destinationDomain;
    //     // // destination = _destination;
    //     // connext = _connext;
    //     // executor = _connext.executor();
    //     // host = _host;
    //     // cfa = _cfa;
    //     // token = _token;

    //     // surely this can't go wrong
    //     IERC20(token.getUnderlyingToken()).approve(address(connext), type(uint256).max);

    //     // register app
    //     host.registerApp(
    //         SuperAppDefinitions.APP_LEVEL_FINAL |
    //         SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
    //         SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
    //         SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
    //     );
    // }

    // demoday hack. this is not permanent.
    bool done;
    error Done();
    function setDomain(address _destination) external {
        if (done) revert Done();
        done = true;
        destination = _destination;
    }

    // //////////////////////////////////////////////////////////////
    // REBALANCER
    // //////////////////////////////////////////////////////////////

    /// @dev Rebalances pools. This sends funds over the bridge to the destination.
    function rebalance() external {
        _sendRebalanceMessage();
    }

    // //////////////////////////////////////////////////////////////
    // SUPER APP CALLBACKS
    // //////////////////////////////////////////////////////////////
    function afterAgreementCreated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 agreementId,
        bytes calldata agreementData,
        bytes calldata, // cbdata
        bytes calldata ctx
    ) external isCallbackValid(agreementClass, superToken) returns (bytes memory) {
        (address sender, ) = abi.decode(agreementData, (address,address));

        ( , int96 flowRate, , ) = cfa.getFlowByID(superToken, agreementId);

        _sendFlowMessage(sender, flowRate);

        return ctx;
    }

    function afterAgreementUpdated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 agreementId,
        bytes calldata agreementData,
        bytes calldata, // cbdata
        bytes calldata ctx
    ) external isCallbackValid(agreementClass, superToken) returns (bytes memory) {
        (address sender, ) = abi.decode(agreementData, (address, address));

        ( , int96 flowRate, , ) = cfa.getFlowByID(superToken, agreementId);

        _sendFlowMessage(sender, flowRate);

        return ctx;
    }

    function afterAgreementTerminated(
        ISuperToken superToken,
        address agreementClass,
        bytes32,
        bytes calldata agreementData,
        bytes calldata, // cbdata
        bytes calldata ctx
    ) external isCallbackValid(agreementClass, superToken) returns (bytes memory) {
        (address sender, ) = abi.decode(agreementData, (address,address));

        _sendFlowMessage(sender, 0);

        return ctx;
    }

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

    /// @dev Sends the flow message across the bridge.
    /// @param account The account streaming.
    /// @param flowRate Flow rate, unadjusted.
    function _sendFlowMessage(address account, int96 flowRate) internal {
        uint256 buffer;

        if (flowRate > 0) {
            // we take a second buffer for the outpool
            buffer = cfa.getDepositRequiredForFlowRate(token, flowRate);

            token.transferFrom(account, address(this), buffer);

            token.downgrade(buffer);
        }

        // encode call
        bytes memory callData = abi.encodeCall(
            IDestinationPool(destination).receiveFlowMessage,
            (account, flowRate)
        );


        uint256 relayerFee = 0;
        uint256 slippage = 0;

        connext.xcall{value: relayerFee}(
            destinationDomain,               // _destination: Domain ID of the destination chain
            destination,                     // _to: address receiving the funds on the destination
            token.getUnderlyingToken(),      // _asset: address of the token contract
            address(this),                      // _delegate: address that can revert or forceLocal on destination
            buffer,                         // _amount: amount of tokens to transfer
            slippage,                        // _slippage: the maximum amount of slippage the user will accept in BPS
            callData                         // _callData
        ); 


        emit FlowMessageSent(account, flowRate);
    }
}
