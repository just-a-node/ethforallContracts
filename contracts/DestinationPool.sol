// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.17;

import {IDestinationPool} from "../interfaces/IDestinationPool.sol";

import {IConnext} from "@connext/nxtp-contracts/contracts/core/connext/interfaces/IConnext.sol";
import {IXReceiver} from "@connext/nxtp-contracts/contracts/core/connext/interfaces/IXReceiver.sol";

import {IConstantFlowAgreementV1} from 
"@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {
    ISuperfluid,
    ISuperToken,
    SuperAppDefinitions
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "https://github.com/transmissions11/solmate/blob/main/src/mixins/ERC4626.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

error Unauthorized();
error InvalidDomain();
error InvalidOriginContract();

abstract contract DestinationPool is IDestinationPool, ERC4626 {

    /// @dev Emitted when connext delivers a flow message.
    /// @param account Account to stream to.
    /// @param flowRate Adjusted flow rate.
    event FlowMessageReceived(
        address indexed account,
        int96 flowRate
    );

    /// @dev Emitted when connext delivers a rebalance message. // TODO Add amount?
    event RebalanceMessageReceived();

    /// @dev Nomad domain of origin contract.
    uint32 public immutable originDomain = 1735353714;

    /// @dev Origin contract address.
    address public immutable originContract;

    /// @dev Connext contracts.
    IConnext public immutable connext = IConnext(0x2334937846Ab2A3FCE747b32587e1A1A2f6EEC5a);

    /// @dev Superfluid contracts.
    ISuperfluid public immutable host = ISuperfluid(0xEB796bdb90fFA0f28255275e16936D25d3418603);
    IConstantFlowAgreementV1 public immutable cfa = IConstantFlowAgreementV1(0x49e565Ed1bdc17F3d220f72DF0857C26FA83F873);
    ISuperToken public immutable token = ISuperToken(0xFB5fbd3B9c471c1109A3e0AD67BfD00eE007f70A);

    /// @dev Virtual "flow rate" of fees being accrued in real time.
    int96 public feeAccrualRate;

    /// @dev Last update's timestamp of the `feeAccrualRate`.
    uint256 public lastFeeAccrualUpdate;

    /// @dev Fees pending that are NOT included in the `feeAccrualRate`
    // TODO this might not be necessary since the full balance is sent on flow update.
    uint256 public feesPending;

    /// @dev Validates message sender, origin, and originContract.
    modifier onlySource(address _originSender, uint32 _origin) {
        require(
        _origin == originDomain &&
            _originSender == originContract &&
            msg.sender == address(connext),
        "Expected source contract on origin domain called by Connext"
        );
        _;
    }

    constructor(
        // uint32 _originDomain,
        address _originContract
        // IConnext _connext,
        // ISuperfluid _host,
        // IConstantFlowAgreementV1 _cfa,
        // ISuperToken _token
    ) ERC4626(
        IERC20(address(token)) 
        // xPool Super DAI
        // string(abi.encodePacked("xPool ", token.name())),
        // // xpDAIx // kek
        // string(abi.encodePacked("xp", token.symbol()))
    ) {
        // originDomain = _originDomain;
        originContract = _originContract;
        // host = _host;
        // cfa = _cfa;
        // token = _token;
        // connext = _connext;

        // approve token to upgrade
        IERC20(token.getUnderlyingToken()).approve(address(token), type(uint256).max);
    }

    // //////////////////////////////////////////////////////////////
    // ERC4626 OVERRIDES
    // //////////////////////////////////////////////////////////////

    /// @dev Total assets including fees not yet rebalanced.
    function totalAssets() public view override returns (uint256) {
        uint256 balance = token.balanceOf(address(this));

        uint256 feesSinceUpdate =
            uint256(uint96(feeAccrualRate)) * (lastFeeAccrualUpdate - block.timestamp);

        return balance + feesPending + feesSinceUpdate;
    }

    // //////////////////////////////////////////////////////////////
    // MESSAGE RECEIVERS
    // //////////////////////////////////////////////////////////////

    string callData;
    /** @notice Authenticated receiver function.
    * @param _callData Calldata containing the new greeting.
    */
    function xReceive(
        bytes32 _transferId,
        uint256 _amount,
        address _asset,
        address _originSender,
        uint32 _origin,
        bytes memory _callData
    ) external  onlySource(_originSender, _origin) returns (bytes memory) {
        // Unpack the _callData
        callData = abi.decode(_callData, (string));
    
    }

    /// @dev Flow message receiver.
    /// @param account Account streaming.
    /// @param flowRate Unadjusted flow rate.
    function receiveFlowMessage(address account, int96 flowRate)
        external
        override
    {
        // 0.1%
        int96 feeFlowRate = flowRate * 10 / 10000;

        // update fee accrual rate
        _updateFeeFlowRate(feeFlowRate);

        // Adjust for fee on the destination for fee computation.
        int96 flowRateAdjusted = flowRate - feeFlowRate;

        // if possible, upgrade all non-super tokens in the pool
        uint256 balance = IERC20(token.getUnderlyingToken()).balanceOf(address(this));

        if (balance > 0) token.upgrade(balance);

        (,int96 existingFlowRate,,) = cfa.getFlow(token, address(this), account);

        bytes memory callData;

        if (existingFlowRate == 0) {
            if (flowRateAdjusted == 0) return; // do not revert
            // create
            callData = abi.encodeCall(
                cfa.createFlow,
                (token, account, flowRateAdjusted, new bytes(0))
            );
        } else if (flowRateAdjusted > 0) {
            // update
            callData = abi.encodeCall(
                cfa.updateFlow,
                (token, account, flowRateAdjusted, new bytes(0))
            );
        } else {
            // delete
            callData = abi.encodeCall(
                cfa.deleteFlow,
                (token, address(this), account, new bytes(0))
            );
        }

        host.callAgreement(cfa, callData, new bytes(0));

        emit FlowMessageReceived(account, flowRateAdjusted);
    }

    /// @dev Rebalance message receiver.
    function receiveRebalanceMessage() external override  {
        uint256 underlyingBalance = IERC20(token.getUnderlyingToken()).balanceOf(address(this));

        token.upgrade(underlyingBalance);

        feesPending = 0;

        emit RebalanceMessageReceived();
    }

    /// @dev Updates the pending fees, feeAccrualRate, and lastFeeAccrualUpdate on a flow call.
    /// Pending fees are set to zero because the flow message always contains the full balance of
    /// the origin pool
    function _updateFeeFlowRate(int96 feeFlowRate) internal {
        feesPending = 0;

        feeAccrualRate += feeFlowRate;

        lastFeeAccrualUpdate = block.timestamp;
    }
}