// SPDX-License-Identifier: MIT

pragma solidity ^0.6.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract Platform is Ownable, Pauseable {

    address public NFT;
    address public dataStore;

    event AddedAuditor(     address indexed _owner, address indexed _auditor);
    event SuspendedAuditor( address indexed _owner, address indexed _auditor);
    event ReinstatedAuditor(address indexed _owner, address indexed _auditor);

    event CompletedAudit(address indexed _auditor, address indexed _contract, bool _approved, string indexed _hash);
    event ChangedDataStore(address indexed _owner, address _dataStore);
    event AuditorMigrated(address indexed _auditor);

    event InitializedNFT(address _NFT);
    event InitializedDataStore(address _dataStore)

    constructor(address _NFT, address _dataStore) Ownable() Pauseable() public {
        NFT = _NFT;
        dataStore = _dataStore;

        emit InitializedNFT(NFT);
        emit InitializedDataStore(dataStore);
    }

    function completeAudit(address _contract, bool _approved, bytes calldata _hash) external {
        require(!paused(), "Adding new audits is paused");

        // Tell the data store that an audit has been completed
        dataStore.call(abi.encodeWithSignature("completeAudit(address, bool, bytes)", _msgSender(), _approved, _hash));

        // Mint a non-fungible token for the auditor as a receipt
        NFT.call(abi.encodeWithSignature("mint(address, address, bool, bytes)", _msgSender(), _contract, _approved, _hash));

        emit CompletedAudit(_msgSender(), _contract, _approved, string(_hash));
    }

    function addAuditor(address _auditor) external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        require(!paused(), "Addition of auditors is paused");

        // Tell the data store to add an auditor
        dataStore.call(abi.encodeWithSignature("addAuditor(address)", _auditor));
        
        emit AddedAuditor(_msgSender(), _auditor);
    }

    function suspendAuditor(address _auditor) external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");

        // Tell the data store to switch the value which indicates whether someone is an auditor to false
        dataStore.call(abi.encodeWithSignature("suspendAuditor(address)", _auditor));
        
        emit SuspendedAuditor(_msgSender(), _auditor);
    }

    function migrate(address _auditor) external {
        // In the next iteration role based permissions will be implemented
        require(_msgSender() == _auditor, "Cannot migrate someone else");

        // Tell the data store to migrate the auditor
        dataStore.call(abi.encodeWithSignature("migrate(address)", _msgSender()));
        
        emit AuditorMigrated(_msgSender());
    }

    function reinstateAuditor(address _auditor) external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        require(!paused(), "Reinstation of auditors is paused");

        // Tell the data store to switch the value which indicates whether someone is an auditor back to true
        dataStore.call(abi.encodeWithSignature("reinstateAuditor(address)", _auditor));
        
        emit ReinstatedAuditor(_msgSender(), _auditor);
    }

    function pause() external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _pause();
    }

    function unpause() external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _unpause();
    }

    function changeDataStore(address _dataStore) external {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");

        dataStore = _dataStore;
        
        emit ChangedDataStore(_msgSender(), dataStore);
    }
}