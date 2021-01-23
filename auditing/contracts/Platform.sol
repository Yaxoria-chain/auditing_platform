// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.4;

import "./Pausable.sol";
import "./IDatastore.sol";
import "./IAuditNFT.sol";
import "./IAuditable.sol";

// TODO: How do you implement the completeAudit, migrateAuditor, contractDestructed via an interface? Prettu sure the caller using the interface would be the contract ...
// TODO: Does the platform really need the same events as the store? Pointless in between?

contract Platform is Pausable {

    /**
     *  @notice The non-fungible token that shall be issued as a receipt to the auditor for their work
     *  @dev A new NFT should be issued with each new iteration of the platform
     */ 
    address public NFT;

    /**
     *  @notice The storage for the auditors and their audits
     *  @dev The store may be swapped out over time
     */
    address public dataStore;

    /**
     *  @notice As new versions are issued the variable will be updated to reflect that
     */
    string public constant version = "Demo: 1";

    /**
     *  @notice Event tracking whenever an auditor is added and who added them
     *  @param _owner The current owner of the platform
     *  @param auditor The auditor that has been added
     */
    event AuditorAdded( address indexed owner, address indexed auditor );

    /**
     *  @notice Event tracking whenever an auditor is suspended and who suspended them, will prevent the auditor from completing future audits
     *  @param _owner The current owner of the platform
     *  @param auditor The auditor who has been blocked for continuing to use the platform to perform audits
     */
    event AuditorSuspended( address indexed owner, address indexed auditor );

    /**
     *  @notice Event tracking whenever an auditor is reinstated and who reinstated them, will allow the auditor to complete audits again
     *  @param _owner The current owner of the platform
     *  @param auditor The auditor who can complete audits again
     */
    event AuditorReinstated( address indexed owner, address indexed auditor );

    /**
     *  @notice Event tracking whenever an auditor has migrated themselves to the new datastore
     *  @param _sender Who initiated the migration
     *  @param auditor The auditor who was migrated to the lateset datastore
     *  @dev when role based permissions are implemented the _sender shall become more meaningful
     */
    event AuditorMigrated( address indexed sender, address indexed auditor );

    /**
     *  @notice Event tracking whenever an audit is completed by an auditor indicating the contract and the result of that audit
     *  @param auditor The auditor who completed the audit
     *  @param contract_ The contract hash that is conventionally used to find the contract
     *  @param approved Bool indicating whether the auditor has approved or opposed the contract
     *  @param creationHash The contract creation hash
     */
    event AuditCompleted( address indexed auditor, address indexed contract_, bool approved, string indexed creationHash );
    
    /**
     *  @notice Event tracking whenever the datastore is being swapped out
     *  @param owner The current owner of the platform
     *  @param dataStore Address meant to be a contract that stores information regarding audits
     */
    event ChangedDataStore( address indexed owner, address dataStore );

    /**
     *  @notice Event confirming that the NFT has been set when deployed
     *  @param _NFT Intended to be a contract that mints an NFT for the auditor post audit
     */
    event InitializedNFT( address NFT );

    /**
     *  @notice Event confirming that the datastore has been set when deployed
     *  @param _dataStore Intended to be a contract that stores the data regarding audits and auditors
     */
    event InitializedDataStore( address dataStore );

    /**
     *  @notice Event indicating the change of state of the datastore which prevents additive actions
     *  @param _sender Who initiated the pause
     *  @param _dataStore Which datastore has been paused
     *  @dev Just in case the owner can still suspend auditors and when role based permissions are implemented the _sender shall become more meaningful
     */
    event PausedDataStore( address indexed sender, address indexed dataStore );

    /**
     *  @notice Event indicating the change of state of the datastore which allows functionality to continue
     *  @param _sender Who unpaused the datastore
     *  @param _dataStore Which datastore has been unpaused
     *  @dev When role based permissions are implemented the _sender shall become more meaningful
     */
    event UnpausedDataStore( address indexed sender, address indexed dataStore );

    event RegisteredContract( address contract_, address deployer );

    event ConfirmedContractRegistration( address contract_, address deployer, address creationHash, address auditor );

    event SetContractAuditor( address contract_, address auditor );

    event ApprovedAudit( address contract_, address auditor );

    event OpposedAudit( address contract_, address auditor );

    /**
     *  @notice Set the NFT to be able to send them to auditors and the datastore that will store the audit data
     *  @param _NFT The non-fungible token that shall be issued as a receipt to the auditor for their work
     *  @param _dataStore The storage for the auditors and their audits
     *  @dev notice Pausable allows us to pause and unpause functionality in case an issue occurs
     */
    constructor( address _NFT, address _dataStore ) Pausable() public {
        NFT = _NFT;
        dataStore = _dataStore;

        emit InitializedNFT( NFT );
        emit InitializedDataStore( dataStore );
    }

    function register( address deployer ) external whenNotPaused() {
        IDatastore( dataStore ).register( _msgSender(), deployer );

        emit RegisteredContract( _msgSender(), deployer );
    }

    function setAuditor( address auditor ) external whenNotPaused() {
        IDatastore( dataStore ).setAuditor( _msgSender(), auditor );

        emit SetContractAuditor( _msgSender(), auditor );
    }

    /**
     *  @notice A deployed contract has a creation hash, store it so that you can access the code post self destruct
     *  @dev When a contract is deployed the first transaction is the contract creation - use that hash
     */
    function confirmRegistration( address contract_, address deployer, address creationHash ) external whenNotPaused() {
        // TODO: best to use string.... creationHash
        IDatastore( dataStore ).confirmRegistration( contract_, deployer, creationHash, _msgSender() );

        emit ConfirmedContractRegistration( contract_, deployer, creationHash, _msgSender() );
    }

    function approveAudit( address contract_ ) external whenNotPaused() {
        require( IDatastore( dataStore ).isAuditor( _msgSender() ), "Valid auditors only");

        IDatastore( dataStore ).approveAudit( contract_, _msgSender() );
        IAuditable( contract_ ).approveAudit( _msgSender() );

        ( _auditor, _deployer, , _creationHash, _approved ) = IDatastore( dataStore ).contractDetails( contract_ );
        IAuditNFT( NFT ).mint( _auditor, contract_, _deployer, _approved, _creationHash );

        emit ApprovedAudit( contract_, _msgSender() );
    }

    /**
     *  @notice Adds a new entry to the datastore post audit and mints the auditor a receipt NFT
     *  @param auditor The auditor who performed the audit
     *  @param _caller The contract that has called the completeAudit function in the platform
     *  @param approved Bool indicating whether the auditor has approved or opposed the contract
     *  @param creationHash The contract creation hash
     */
    function completeAudit( address auditor, address deployer, address creationHash, bool approved ) external whenNotPaused() {  
        // Update the contract record in the data store and mint a non-fungible token for the auditor as a receipt
        IDatastore( dataStore ).completeAudit( auditor, deployer, _msgSender(), creationHash, approved );
        IAuditNFT( NFT ).mint( auditor, _msgSender(), deployer, approved, creationHash );

        emit AuditCompleted( auditor, _msgSender(), approved, string( creationHash ) ); // TODO: check if you can stringify the address or require manual conversion
    }

    /**
     *  @notice Adds a new auditor to the current datastore
     *  @param auditor The auditor who has been added
     */
    function addAuditor( address auditor ) external onlyOwner() whenNotPaused() {
        IDatastore( dataStore ).addAuditor( auditor );
        emit AuditorAdded( _msgSender(), auditor );
    }

    /**
     *  @notice Prevents the auditor from performing any audits
     *  @param auditor The auditor who is suspended
     */
    function suspendAuditor( address auditor ) external onlyOwner() {
        IDatastore( dataStore ).suspendAuditor( auditor );
        emit AuditorSuspended( _msgSender(), auditor );
    }

    /**
     *  @notice Adds a record of a previously valid audit to the newer datastore
     *  @param auditor The auditor who is migrated
     */
    function migrateAuditor() external {
        // TODO: Role based permissions
        IDatastore( dataStore ).migrateAuditor( _msgSender() );
        emit AuditorMigrated( _msgSender() );
    }

    /**
     *  @notice Allows the auditor to perform audits again
     *  @param auditor The auditor who is reinstated
     */
    function reinstateAuditor( address auditor ) external onlyOwner() whenNotPaused() {
        IDatastore( dataStore ).reinstateAuditor( auditor );
        emit AuditorReinstated( _msgSender(), auditor );
    }

    /**
     *  @notice Blocks functionality that prevents writing of additive data to the store
     *  @dev You can suspend just in case
     */
    function pauseDataStore() external onlyOwner() {
        IDatastore( dataStore ).pause();
        emit PausedDataStore( _msgSender(), dataStore );
    }

    /**
     *  @notice Unblocks functionality that prevented writing to the store
     */
    function unpauseDataStore() external onlyOwner() {
        IDatastore( dataStore ).unpause();
        emit UnpausedDataStore( _msgSender(), dataStore );
    }

    /**
     *  @notice Changes the datastore to a newer version
     *  @param _dataStore Address meant to be a contract that stores information regarding audits
     */
    function changeDataStore( address _dataStore ) external onlyOwner() {
        // TODO: note regarding permissions
        IDatastore( _dataStore ).linkDataStore( dataStore );
  
        dataStore = _dataStore;
        
        emit ChangedDataStore( _msgSender(), dataStore );
    }
}

