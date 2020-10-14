// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Auditable.sol";

contract ToDo is Ownable, Auditable {

    struct Task {
        bool completed;
        bytes task;
    }

    mapping(address => Task[]) tasks;

    constructor() Ownable() Auditable() public {};

    function viewTasks() public view isAudited() returns () {
        return tasks;
    }

    function completeTask(uint256 _taskID) public isAudited() {
        require(_taskID <= tasks[msg.sender].length - 1, "Invalid task ID");
        require(!tasks[msg.sender][_taskID].completed, "Task has already been completed");

        tasks[msg.sender][_taskID].completed = true;
    }

    function undoTask(uint256 _taskID) public isAudited() {
        require(_taskID <= tasks[msg.sender].length - 1, "Invalid task ID");
        require(!tasks[msg.sender][_taskID].completed, "Task has not been completed");

        tasks[msg.sender][_taskID].completed = false;
    }
}