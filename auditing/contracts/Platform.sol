// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.10;

import "./Pausable.sol";

contract Platform is Pausable {

    address public NFT;
    address public dataStore;

    string public constant version = "Demo: 1";

    event AddedAuditor(     address indexed _owner, address indexed _auditor);
    event SuspendedAuditor( address indexed _owner, address indexed _auditor);
    event ReinstatedAuditor(address indexed _owner, address indexed _auditor);

    event CompletedAudit(   address indexed _auditor, address indexed _contract, bool _approved, string indexed _hash);
    event ChangedDataStore( address indexed _owner, address _dataStore);
    event AuditorMigrated(  address indexed _sender, address indexed _auditor);

    event InitializedNFT(address _NFT);
    event InitializedDataStore(address _dataStore);

    event PausedDataStore(  address indexed _sender, address indexed _dataStore);
    event UnpausedDataStore(address indexed _sender, address indexed _dataStore);

    constructor(address _NFT, address _dataStore) Pausable() public {
        NFT = _NFT;
        dataStore = _dataStore;

        emit InitializedNFT(NFT);
        emit InitializedDataStore(dataStore);
    }

    function completeAudit( address _auditor, address _contract, bool _approved, bytes calldata _hash) external whenNotPaused() {
        // Tell the data store that an audit has been completed
        (bool _storeSuccess, ) = dataStore.call(abi.encodeWithSignature("completeAudit(address,bool,bytes)", _auditor, _approved, _hash));

        require(_storeSuccess, "Unknown error when adding audit record to the data store");

        // Mint a non-fungible token for the auditor as a receipt
        (bool _NFTSuccess, ) = NFT.call(abi.encodeWithSignature("mint(address,address,bool,bytes)", _auditor, _contract, _approved, _hash));
        
        require(_NFTSuccess, "Unknown error with the minting of the Audit NFT");

        emit CompletedAudit(_msgSender(), _contract, _approved, string(_hash));
    }

    function addAuditor(address _auditor) external onlyOwner() whenNotPaused() {
        // Tell the data store to add an auditor
        (bool _success, ) = dataStore.call(abi.encodeWithSignature("addAuditor(address)", _auditor));

        require(_success, "Unknown error when adding auditor to the data store");
        
        emit AddedAuditor(_msgSender(), _auditor);
    }

    function suspendAuditor(address _auditor) external onlyOwner() {
        // Tell the data store to switch the value which indicates whether someone is an auditor to false
        (bool _success, ) = dataStore.call(abi.encodeWithSignature("suspendAuditor(address)", _auditor));

        require(_success, "Unknown error when suspending auditor in the data store");
        
        emit SuspendedAuditor(_msgSender(), _auditor);
    }

    function migrate(address _auditor) external {
        // In the next iteration role based permissions will be implemented
        require(_msgSender() == _auditor, "Cannot migrate someone else");

        // Tell the data store to migrate the auditor
        (bool _success, ) = dataStore.call(abi.encodeWithSignature("migrate(address,address)", _msgSender(), _auditor));

        require(_success, "Unknown error when migrating auditor");
        
        emit AuditorMigrated(_msgSender(), _auditor);
    }

    function reinstateAuditor(address _auditor) external onlyOwner() whenNotPaused() {
        // Tell the data store to switch the value which indicates whether someone is an auditor back to true
        (bool _success, ) = dataStore.call(abi.encodeWithSignature("reinstateAuditor(address)", _auditor));

        require(_success, "Unknown error when reinstating auditor in the data store");
        
        emit ReinstatedAuditor(_msgSender(), _auditor);
    }

    function pauseDataStore() external onlyOwner() {
        (bool _success, ) = dataStore.call(abi.encodeWithSignature("pause()"));
        
        require(_success, "Unknown error when pausing the data store");

        emit PausedDataStore(_msgSender(), dataStore);
    }

    function unpauseDataStore() external onlyOwner() {
        (bool _success, ) = dataStore.call(abi.encodeWithSignature("unpause()"));

        require(_success, "Unknown error when unpausing the data store");

        emit UnpausedDataStore(_msgSender(), dataStore);
    }

    function changeDataStore(address _dataStore) external onlyOwner() whenPaused() {
        dataStore = _dataStore;
        
        emit ChangedDataStore(_msgSender(), dataStore);
    }
}