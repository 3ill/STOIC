// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract Stoic {
    event userCreated(address indexed _userAddress, string _name);
    event taskCreated(
        address indexed _creatorAddress,
        uint indexed _id,
        uint indexed _stakedAmount
    );
    event taskCompleted(
        address indexed _userAddress,
        uint indexed _id,
        uint indexed _stakedAmount,
        uint _completionTime
    );
    enum State {
        notStarted,
        inProgress,
        completed
    }

    struct User {
        address Address;
        string Name;
        uint256 numberOfTasksCreated;
        uint256 numberOfTasksCompleted;
        uint256 numberOfBadgesAwarded;
        uint256 numberOfBountiesCreated;
        uint256 numberOfBountiesCompleted;
    }

    struct Task {
        uint256 id;
        address creatorAddress;
        bytes32 taskDescription;
        State state;
        uint256 stakedAmount;
        uint256 timestamp;
        uint256 deadline;
        uint256 bountyStakeAmount;
        uint256 lockPeriod;
        uint256 unlockTime;
        bool isFundsReleased;
        bool isBountyIssued;
        bool isBountyClaimed;
        address bountyClaimedBy;
    }

    address private immutable owner;

    uint256 public usersCounter;
    uint256 public taskCounter;
    uint256 public completedTasksCounter;
    uint256 public numberOfBountiesCreated;
    uint256 public numberOfBountiesCompleted;

    mapping(uint => Task) private allTasks;
    mapping(address => Task) private userTasks;
    mapping(address => User) private addressToUser;
    mapping(uint => Task) private bounties;

    constructor() {
        owner = msg.sender;
    }

    //? Internal functions

    function mintNFT() internal {}

    function returnTaskFromId(
        uint _taskId
    ) internal view returns (Task storage) {
        return allTasks[_taskId];
    }

    function convertStringToBytes(
        string memory _string
    ) internal pure returns (bytes32) {
        bytes32 result;

        assembly {
            result := mload(add(_string, 32))
        }

        return result;
    }

    //? External & Public functions
    function createUser(string memory _name) external {
        usersCounter++;
        User memory user = User({
            Address: msg.sender,
            Name: _name,
            numberOfTasksCreated: 0,
            numberOfTasksCompleted: 0,
            numberOfBadgesAwarded: 0,
            numberOfBountiesCreated: 0,
            numberOfBountiesCompleted: 0
        });

        addressToUser[msg.sender] = user;
        emit userCreated(msg.sender, _name);
    }

    function createTask(
        string memory _description,
        uint256 _amountToStake,
        uint256 _taskDeadline,
        uint256 _bountyStakeAmount,
        uint256 _lockPeriod
    ) external payable {
        require(_amountToStake > 0, "Amount is too low for staking");
        taskCounter++;
        Task memory newTask = Task({
            id: taskCounter,
            creatorAddress: msg.sender,
            taskDescription: convertStringToBytes(_description),
            state: State.inProgress,
            stakedAmount: _amountToStake,
            timestamp: block.timestamp,
            deadline: _taskDeadline,
            bountyStakeAmount: _bountyStakeAmount,
            lockPeriod: _lockPeriod,
            unlockTime: block.timestamp + _lockPeriod,
            isFundsReleased: false,
            isBountyIssued: _bountyStakeAmount > 0 ? true : false,
            isBountyClaimed: false,
            bountyClaimedBy: address(0)
        });
        addressToUser[msg.sender].numberOfTasksCreated++;
        if (_bountyStakeAmount > 0) {
            addressToUser[msg.sender].numberOfBountiesCreated++;
            numberOfBountiesCreated++;
            bounties[numberOfBountiesCreated] = newTask;
        }

        //? send the stakedAmount to the contract
        (bool sent, ) = payable(address(this)).call{value: _amountToStake}("");
        require(sent, "This transaction failed");

        allTasks[newTask.id] = newTask;
        userTasks[msg.sender] = newTask;

        emit taskCreated(msg.sender, newTask.id, _amountToStake);
    }

    function completeTask(
        uint _taskId
    ) external returns (string memory _message) {
        completedTasksCounter++;
        bool deadlineExceeded = false;

        Task storage task = returnTaskFromId(_taskId);

        require(
            msg.sender == task.creatorAddress,
            "not the creator of this task"
        );

        require(
            task.state != State.completed,
            "task has already been completed"
        );

        if (block.timestamp > (task.timestamp + task.deadline)) {
            deadlineExceeded = true;
        }

        require(!task.isFundsReleased, "This task has been completed");

        task.state = State.completed;
        addressToUser[msg.sender].numberOfTasksCompleted++;

        if (task.lockPeriod > 0) {
            require(
                block.timestamp >= task.unlockTime,
                "amount staked is locked until unlock time is reached"
            );
        }
        uint256 amountToSend;
        if (task.bountyStakeAmount > 0) {
            amountToSend = task.stakedAmount - task.bountyStakeAmount;
        } else {
            amountToSend = task.stakedAmount;
        }

        if (deadlineExceeded) {
            _message = "deadline exceeded, staked amount will be sent to a charity organization";
        } else {
            (bool sent, ) = payable(msg.sender).call{value: amountToSend}("");
            require(sent, "this transaction failed");
        }

        emit taskCompleted(msg.sender, _taskId, amountToSend, block.timestamp);
    }

    function setBounty() public {}

    function claimBounty() external {}

    function lockStake() external {}
}
