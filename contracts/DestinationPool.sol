// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.17;
import "hardhat/console.sol";


import {IDestinationPool} from "../interfaces/IDestinationPool.sol";

import {IConnext} from "@connext/smart-contracts/contracts/core/connext/interfaces/IConnext.sol";
import {IXReceiver} from "@connext/smart-contracts/contracts/core/connext/interfaces/IXReceiver.sol";

import {IConstantFlowAgreementV1} from  
"@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {
    ISuperfluid,
    ISuperToken,
    SuperAppDefinitions
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {
    SuperTokenV1Library
} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

// import "../interfaces/IERC4626.sol";
import "../interfaces/IERC20.sol";

// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "https://github.com/transmissions11/solmate/blob/main/src/mixins/ERC4626.sol";
// import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

error Unauthorized();
error InvalidDomain(); 
error InvalidOriginContract();

contract DestinationPool is IXReceiver, AutomationCompatibleInterface, IDestinationPool {
    using SuperTokenV1Library for ISuperToken;
 
    event FlowMessageReceived(address indexed sender, address indexed receiver, int96 flowRate, string streamActionType);

    /// @dev Emitted when connext delivers a rebalance message. // TODO Add amount?
    event RebalanceMessageReceived();

    /// @dev Nomad domain of origin contract.
    uint32 public immutable originDomain = 1735353714;

    /// @dev Origin contract address.
    address public originContract;

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

    // constructor(
    //     address _originContract
    // ) ERC4626(
    //     IERC20(address(token)), 
    //     // xPool Super DAI
    //     string(abi.encodePacked("xPool ", token.name())),
    //     // xpDAIx // kek
    //     string(abi.encodePacked("xp", token.symbol()))
    // ) {
    //     originContract = _originContract;

    //     // approve token to upgrade
    //     IERC20(token.getUnderlyingToken()).approve(address(token), type(uint256).max);
    // }

    constructor( 
        address _originContract
        // ERC20 _underlying,
        // string memory _name,
        // string memory _symbol
    ) {
        originContract = _originContract; 

        // approve token to upgrade
        // IERC20(token.getUnderlyingToken()).approve();
    }

    function changeOriginContract(address origin) public {
        originContract = origin;
    }

    // //////////////////////////////////////////////////////////////
    // MESSAGE RECEIVERS
    // //////////////////////////////////////////////////////////////
    uint256 lastTimeStamp;
    uint interval;

    // stream variables
    uint public streamActionType; // 1 -> Start stream, 2 -> Topup stream, 3 -> Delete stream
    address public sender;
    address public receiver;
    int96 public flowRate;
    uint256 public startTime;
    uint public amount;
    uint public testIncrement;

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        // upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
        upkeepNeeded = streamActionType == 1;
        // We don't use the checkData in this example. The checkData is defined when the Upkeep was registered.
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        //We highly recommend revalidating the upkeep in the performUpkeep function
        // if ((block.timestamp - lastTimeStamp) > interval) {
            
        // }
        // IERC20(token.getUnderlyingToken()).approve(address(token), amount); //approving the upgradation
        // ISuperToken(address(token)).upgrade(amount); // upgrading
        testIncrement = testIncrement + 1; 
        streamActionType = 0;

        // We don't use the performData in this example. The performData is generated by the Automation Node's call to your checkUpkeep function
    }

    string public callData;
    uint256 public ping = 0;
    event updatingPing(address sender, uint256 pingCount);

    function xReceive(
        bytes32 _transferId,
        uint256 _amount,
        address _asset,
        address _originSender,
        uint32 _origin,
        bytes memory _callData
    ) external returns (bytes memory) {
        // Unpack the _callData

        (streamActionType, sender, receiver, flowRate, startTime) = abi.decode(_callData, (uint, address, address, int96, uint256));
        amount = _amount;
        // some event will be triggered here which will call the chainlink 
        // automation contracts then it will run the corresponding superfluid
        // functions in this contract.
        console.log("Received calldata ", callData);
        updatePing(_originSender); 
        // approveSuperToken(address(_asset), _amount);
    }

    event UpgradeToken(address indexed baseToken, uint256 amount);
    function approveSuperToken(address _asset, uint256 _amount) public {
        IERC20(_asset).approve(address(token), _amount); // approving the superToken contract to upgrade TEST
        ISuperToken(address(token)).upgrade(_amount);
        emit UpgradeToken(_asset, _amount);
    }

    function updatePing(address sender) public {
        ping = ping+1;
        emit updatingPing (sender, ping);
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

        // emit FlowMessageReceived(account, flowRateAdjusted);
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