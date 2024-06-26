// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import { IRocketStorage } from "./interfaces/IRocketStorage.sol";
import { IRocketDepositPool } from "./interfaces/IRocketDepositPool.sol";
import { IRocketTokenRETH } from "./interfaces/IRocketTokenRETH.sol";

contract MiddleMan {
    // immutables: no SLOAD
    uint256 public immutable timeLockInit;
    uint256 public immutable timelock;

    // storage varables
    address public owner;
    uint256 public totalSaved;
    uint256 public savingsAmt;
    IRocketStorage rocketStorage;
    mapping(address => uint256) balances;

    // errors
    error FundsLocked();
    error InsuffientValue();
    error Unauthorized();

    constructor(address _owner, uint256 _savingsAmt, uint256 _timelock, address _rocketStorageAddress) {
        owner = _owner;
        savingsAmt = _savingsAmt;
        timelock = _timelock;
        rocketStorage = IRocketStorage(_rocketStorageAddress);

        // initialize timplock
        timeLockInit = block.timestamp;
    }

    function entryPoint(address _target, bytes memory _calldata)
        public
        payable
        onlyOwner
        returns (bool success, bytes memory returnData)
    {
        // ensure value was senta
        if (msg.value < savingsAmt) {
            revert InsuffientValue();
        }

        // increment total saved
        totalSaved += msg.value;

        // forward call to destination contract
        (success, returnData) = _target.call(_calldata);
    }

    function changeOwner(address _newOwner) public onlyOwner {
        owner = _newOwner;
    }

    function withdraw(uint256 amt) public onlyOwner {
        if (block.timestamp < timeLockInit + timelock) {
            revert FundsLocked();
        }

        payable(owner).transfer(amt);
    }

    function changeSavingsAmt(uint256 _savingsAmt) public onlyOwner {
        savingsAmt = _savingsAmt;
    }

    /// @notice Allows a user to send in Ether, which is then forwarded on to RocketPool
    function stake() public payable {
        // Check deposit amount
        require(msg.value > 0, "Invalid deposit amount");

        // 1. Instantiate RocketDepositPool
        address rocketDepositPoolAddress =
            rocketStorage.getAddress(keccak256(abi.encodePacked("contract.address", "rocketDepositPool")));
        IRocketDepositPool rocketDepositPool = IRocketDepositPool(rocketDepositPoolAddress);

        // 2. Instantiate RocketTokenRETH
        address rocketTokenRETHAddress =
            rocketStorage.getAddress(keccak256(abi.encodePacked("contract.address", "rocketTokenRETH")));
        IRocketTokenRETH rocketTokenRETH = IRocketTokenRETH(rocketTokenRETHAddress);

        // 3. Get balance before
        uint256 rethBalance1 = rocketTokenRETH.balanceOf(address(this));

        // 4. Deposit ETH to RocketPool
        rocketDepositPool.deposit{ value: msg.value }();

        // 5. Ensure the balance of RETH increased
        uint256 rethBalance2 = rocketTokenRETH.balanceOf(address(this));

        require(rethBalance2 > rethBalance1, "No rETH was minted");

        // 6. Update user's balance
        uint256 rethMinted = rethBalance2 - rethBalance1;
        balances[msg.sender] += rethMinted;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    receive() external payable { }
}
