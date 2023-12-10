// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

//todo: automate the mint nft function
//todo: autmoate stake disbursement when a lock function is available
//todo: test set bounty and test bounty function
//todo: if there is some unclaimed bounty set in the task, send back to the creator when marked as completed

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
    event bountySet(
        address indexed _createdBy,
        uint indexed _id,
        uint indexed _bountyAmount
    );
    event bountyClaimed(
        address indexed _claimedBy,
        uint indexed _id,
        uint indexed _bountyAmount
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

    mapping(uint => Task) public allTasks;
    mapping(uint => Task) private bounties;
    mapping(address => User) private addressToUser;
    mapping(address => bool) private isUser;

    constructor() {
        owner = msg.sender;
    }

    modifier taskExsists(uint _taskId) {
        require(_taskId <= taskCounter, "This task does not exist");
        _;
    }

    modifier onlyUsers() {
        require(
            isUser[msg.sender] == true,
            "Only users can call this function"
        );
        _;
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

    function checkLockPeriod(uint _taskId) internal view returns (bool) {
        bool isLockExceeded;
        Task storage task = returnTaskFromId(_taskId);

        if (
            (task.lockPeriod > 0 && block.timestamp >= task.unlockTime) ||
            task.lockPeriod == 0
        ) {
            isLockExceeded = true;
        } else {
            isLockExceeded = false;
        }

        return isLockExceeded;
    }

    function calculateBalance(
        uint _taskId
    ) internal view returns (uint _balance) {
        Task storage task = returnTaskFromId(_taskId);
        uint balance;

        task.bountyStakeAmount > 0
            ? balance = task.stakedAmount - task.bountyStakeAmount
            : balance = task.stakedAmount;

        return balance;
    }

    function checkDeadline(
        uint _taskId
    ) internal view returns (bool isExceeded) {
        Task storage task = returnTaskFromId(_taskId);
        block.timestamp > (task.timestamp + task.deadline)
            ? isExceeded = true
            : isExceeded = false;
    }

    //? External & Public functions
    function createUser(string memory _name) external {
        require(!isUser[msg.sender], "Already a user!");
        usersCounter++;
        isUser[msg.sender] = true;
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
        uint256 _taskDeadline,
        uint256 _bountyStakeAmount,
        uint256 _lockPeriod
    ) external payable {
        require(
            isUser[msg.sender] == true,
            "Only registered users can create tasks"
        );
        require(msg.value > 0, "Amount is too low for staking");
        taskCounter++;
        uint newTaskDeadline = _taskDeadline + 0 seconds;
        uint lockTime = _lockPeriod + 0 seconds;
        uint256 newUnlockTime;
        uint amountToStake = msg.value;

        _lockPeriod > 0
            ? newUnlockTime = block.timestamp + lockTime
            : newUnlockTime = 0;

        Task memory newTask = Task({
            id: taskCounter,
            creatorAddress: msg.sender,
            taskDescription: convertStringToBytes(_description),
            state: State.inProgress,
            stakedAmount: amountToStake,
            timestamp: block.timestamp,
            deadline: newTaskDeadline,
            bountyStakeAmount: _bountyStakeAmount,
            lockPeriod: _lockPeriod,
            unlockTime: newUnlockTime,
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
        (bool sent, ) = payable(address(this)).call{value: amountToStake}("");
        require(sent, "This transaction failed");

        allTasks[newTask.id] = newTask;

        emit taskCreated(msg.sender, newTask.id, amountToStake);
    }

    function completeTask(
        uint _taskId
    ) external taskExsists(_taskId) returns (string memory _message) {
        completedTasksCounter++;

        Task storage task = returnTaskFromId(_taskId);

        require(
            msg.sender == task.creatorAddress,
            "not the creator of this task"
        );

        require(
            task.state != State.completed,
            "task has already been completed"
        );

        require(!task.isFundsReleased, "This task has been completed");

        task.state = State.completed;
        addressToUser[msg.sender].numberOfTasksCompleted++;
        uint256 amountToSend;

        bool isLockExceeded = checkLockPeriod(_taskId);
        bool isDeadlineExceeded = checkDeadline(_taskId);

        if (isLockExceeded == true) {
            amountToSend = calculateBalance(_taskId);
            if (isDeadlineExceeded) {
                _message = "Deadline Exceeded, funds sent to charity";
            } else {
                payable(msg.sender).transfer(amountToSend);
            }
        } else {
            _message = "Funds are still locked";
        }

        emit taskCompleted(msg.sender, _taskId, amountToSend, block.timestamp);
    }

    function setBounty(
        uint256 _taskId
    ) external payable taskExsists(_taskId) onlyUsers {
        Task storage task = returnTaskFromId(_taskId);
        require(msg.value > 0, "invalid bounty");
        uint _bountyAmount = msg.value;
        require(
            task.state != State.completed,
            "Can't set bounty on a completed task"
        );
        task.bountyStakeAmount += _bountyAmount;
        task.isBountyIssued = true;
        addressToUser[msg.sender].numberOfBountiesCreated++;

        (bool success, ) = payable(address(this)).call{value: _bountyAmount}(
            ""
        );
        require(success, "This transaction failed");

        emit bountySet(msg.sender, _taskId, _bountyAmount);
    }

    function claimBounty(uint _taskId) external taskExsists(_taskId) onlyUsers {
        Task storage task = returnTaskFromId(_taskId);
        require(
            task.bountyStakeAmount > 0,
            "There's no bounty available to claim"
        );
        require(!task.isBountyClaimed, "Bounty has already been claimed");
        uint amount = task.bountyStakeAmount;

        task.isBountyClaimed = true;
        task.bountyClaimedBy = msg.sender;
        addressToUser[msg.sender].numberOfBountiesCompleted++;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "This transaction failed");

        emit bountyClaimed(msg.sender, _taskId, amount);
    }

    function lockStake(uint _taskId, uint _time) external taskExsists(_taskId) {
        Task storage task = returnTaskFromId(_taskId);

        require(
            msg.sender == task.creatorAddress,
            "not the creator of this task"
        );
        require(task.lockPeriod == 0, "There's already a lock timer");
        require(_time > 0, "time cannot be 0");
        uint locktime = _time + 0 seconds;
        task.lockPeriod = locktime;
        task.unlockTime = block.timestamp + locktime;
        task.isFundsReleased = false;
    }

    function unlockFunds(uint _taskId) external taskExsists(_taskId) {
        Task storage task = returnTaskFromId(_taskId);

        require(
            msg.sender == task.creatorAddress,
            "not the creator of this task"
        );
        require(task.unlockTime <= block.timestamp, "Funds are still locked");
        require(!task.isFundsReleased, "Funds already released");

        task.isFundsReleased = true;
        payable(msg.sender).transfer(calculateBalance(_taskId));
    }

    receive() external payable {}
}
