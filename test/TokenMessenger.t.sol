/* SPDX-License-Identifier: UNLICENSED
 *
 * Copyright (c) 2022, Circle Internet Financial Trading Company Limited.
 * All rights reserved.
 *
 * Circle Internet Financial Trading Company Limited CONFIDENTIAL
 *
 * This file includes unpublished proprietary source code of Circle Internet
 * Financial Trading Company Limited, Inc. The copyright notice above does not
 * evidence any actual or intended publication of such source code. Disclosure
 * of this source code or any related proprietary information is strictly
 * prohibited without the express written permission of Circle Internet Financial
 * Trading Company Limited.
 */
pragma solidity ^0.7.6;

import "../lib/forge-std/src/Test.sol";
import "../src/TokenMessenger.sol";
import "../src/messages/Message.sol";
import "../src/messages/BurnMessage.sol";
import "../src/MessageTransmitter.sol";
import "../src/TokenMinter.sol";
import "./mocks/MockMintBurnToken.sol";
import "./TestUtils.sol";

contract TokenMessengerTest is Test, TestUtils {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using BurnMessage for bytes29;

    // Events
    /**
     * @notice Emitted when a remote TokenMessenger is added
     * @param _domain remote domain
     * @param _tokenMessenger TokenMessenger on remote domain
     */
    event RemoteTokenMessengerAdded(
        uint32 indexed _domain,
        bytes32 indexed _tokenMessenger
    );

    /**
     * @notice Emitted when a remote TokenMessenger is removed
     * @param _domain remote domain
     * @param _tokenMessenger TokenMessenger on remote domain
     */
    event RemoteTokenMessengerRemoved(
        uint32 indexed _domain,
        bytes32 indexed _tokenMessenger
    );

    /**
     * @notice Emitted when a local minter is added
     * @param _localMinter address of local minter
     * @notice Emitted when a local minter is added
     */
    event LocalMinterAdded(address indexed _localMinter);

    /**
     * @notice Emitted when the local minter is removed
     * @param localMinter address of local minter
     * @notice Emitted when the local minter is removed
     */
    event LocalMinterRemoved(address indexed localMinter);

    /**
     * @notice Emitted when a new message is dispatched
     * @param message Raw bytes of message
     */
    event MessageSent(bytes message);

    /**
     * @notice Emitted when a DepositForBurn message is sent
     * @param nonce unique nonce reserved by message
     * @param burnToken address of token burnt on source domain
     * @param amount deposit amount
     * @param depositor address where deposit is transferred from
     * @param mintRecipient address receiving minted tokens on destination domain as bytes32
     * @param destinationDomain destination domain
     * @param destinationTokenMessenger address of TokenMessenger on destination domain as bytes32
     * @param destinationCaller authorized caller as bytes32 of receiveMessage() on destination domain, if not equal to bytes32(0).
     * If equal to bytes32(0), any address can call receiveMessage().
     */
    event DepositForBurn(
        uint64 indexed nonce,
        address indexed burnToken,
        uint256 indexed amount,
        address depositor,
        bytes32 mintRecipient,
        uint32 destinationDomain,
        bytes32 destinationTokenMessenger,
        bytes32 destinationCaller
    );

    /**
     * @notice Emitted when tokens are minted
     * @param _mintRecipient recipient address of minted tokens
     * @param _amount amount of minted tokens
     * @param _mintToken contract address of minted token
     */
    event MintAndWithdraw(
        address indexed _mintRecipient,
        uint256 indexed _amount,
        address indexed _mintToken
    );

    // Constants
    uint32 localDomain = 0;
    uint32 remoteDomain = 1;
    bytes32 remoteTokenMessenger;
    address owner = vm.addr(1506);
    uint32 messageBodyVersion = 1;
    uint256 approveAmount = 10;
    uint256 mintAmount = 9;

    TokenMessenger localTokenMessenger;
    TokenMessenger destTokenMessenger;
    MessageTransmitter localMessageTransmitter =
        new MessageTransmitter(
            localDomain,
            attester,
            maxMessageBodySize,
            version
        );
    MessageTransmitter remoteMessageTransmitter =
        new MessageTransmitter(
            remoteDomain,
            attester,
            maxMessageBodySize,
            version
        );
    MockMintBurnToken localToken = new MockMintBurnToken();
    MockMintBurnToken destToken = new MockMintBurnToken();
    TokenMinter localTokenMinter = new TokenMinter();
    TokenMinter destTokenMinter = new TokenMinter();

    function setUp() public {
        localTokenMessenger = new TokenMessenger(
            address(localMessageTransmitter),
            messageBodyVersion
        );

        linkTokenPair(
            localTokenMinter,
            address(localToken),
            remoteDomain,
            remoteTokenMessenger
        );

        linkTokenPair(
            destTokenMinter,
            address(destToken),
            localDomain,
            Message.addressToBytes32(address(localToken))
        );

        localTokenMessenger.addLocalMinter(address(localTokenMinter));

        destTokenMessenger = new TokenMessenger(
            address(remoteMessageTransmitter),
            messageBodyVersion
        );

        remoteTokenMessenger = Message.addressToBytes32(
            address(destTokenMessenger)
        );

        localTokenMessenger.addRemoteTokenMessenger(
            remoteDomain,
            remoteTokenMessenger
        );

        destTokenMessenger.addLocalMinter(address(destTokenMinter));

        destTokenMessenger.addRemoteTokenMessenger(
            localDomain,
            Message.addressToBytes32(address(localTokenMessenger))
        );

        localTokenMinter.addLocalTokenMessenger(address(localTokenMessenger));
        destTokenMinter.addLocalTokenMessenger(address(destTokenMessenger));
    }

    function testDepositForBurn_revertsIfNoRemoteTokenMessengerExistsForDomain(
        address _relayerAddress,
        uint256 _amount
    ) public {
        vm.assume(_amount > 0);
        bytes32 _mintRecipient = Message.addressToBytes32(vm.addr(1505));

        TokenMessenger _tokenMessenger = new TokenMessenger(
            _relayerAddress,
            messageBodyVersion
        );

        vm.expectRevert("No TokenMessenger for domain");
        _tokenMessenger.depositForBurn(
            _amount,
            remoteDomain,
            _mintRecipient,
            address(localToken)
        );
    }

    function testDepositForBurn_revertsIfLocalMinterIsNotSet(
        uint256 _amount,
        bytes32 _mintRecipient
    ) public {
        TokenMessenger _tokenMessenger = new TokenMessenger(
            address(localMessageTransmitter),
            messageBodyVersion
        );

        _tokenMessenger.addRemoteTokenMessenger(
            remoteDomain,
            remoteTokenMessenger
        );

        vm.assume(_amount > 0);
        vm.expectRevert("Local minter is not set");
        _tokenMessenger.depositForBurn(
            _amount,
            remoteDomain,
            _mintRecipient,
            address(localToken)
        );
    }

    function testDepositForBurn_revertsIfTransferAmountIsZero() public {
        uint256 _amount = 0;

        vm.expectRevert("Amount must be nonzero");
        localTokenMessenger.depositForBurn(
            _amount,
            remoteDomain,
            remoteTokenMessenger,
            address(localToken)
        );
    }

    function testDepositForBurn_revertsIfTransferAmountExceedsAllowance(
        uint256 _amount
    ) public {
        vm.assume(_amount > 0);
        // Fails because approve() was never called, allowance is 0.
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        localTokenMessenger.depositForBurn(
            _amount,
            remoteDomain,
            remoteTokenMessenger,
            address(localToken)
        );
    }

    function testDepositForBurn_revertsTransferringInsufficientFunds(
        uint256 _amount
    ) public {
        uint256 _approveAmount = 10;
        uint256 _transferAmount = 1;

        vm.assume(_amount > _transferAmount);
        vm.assume(_amount <= _approveAmount);
        address _spender = address(localTokenMessenger);

        localToken.mint(owner, _transferAmount);

        vm.prank(owner);
        localToken.approve(_spender, _approveAmount);

        vm.prank(owner);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        localTokenMessenger.depositForBurn(
            _amount,
            remoteDomain,
            remoteTokenMessenger,
            address(localToken)
        );
    }

    function testDepositForBurn_revertsOnFailedTokenTransfer(uint256 _amount)
        public
    {
        vm.prank(owner);
        vm.mockCall(
            address(localToken),
            abi.encodeWithSelector(MockMintBurnToken.transferFrom.selector),
            abi.encode(false)
        );
        vm.assume(_amount > 0);
        vm.expectRevert("Transfer operation failed");
        localTokenMessenger.depositForBurn(
            _amount,
            remoteDomain,
            remoteTokenMessenger,
            address(localToken)
        );
    }

    function testDepositForBurn_succeeds(uint256 _amount) public {
        vm.assume(_amount > 0);
        vm.assume(_amount <= mintAmount);
        address _mintRecipientAddr = vm.addr(1505);

        _depositForBurn(_mintRecipientAddr, _amount);
    }

    function testDepositForBurn_returnsNonzeroNonce(address _mintRecipientAddr)
        public
    {
        uint64 _nonce0 = localMessageTransmitter.sendMessage(
            remoteDomain,
            recipient,
            messageBody
        );
        assertEq(uint256(_nonce0), 0);

        uint64 _nonce1 = localMessageTransmitter.sendMessage(
            remoteDomain,
            recipient,
            messageBody
        );
        assertEq(uint256(_nonce1), 1);

        _depositForBurn(_mintRecipientAddr, 5);
    }

    function testDepositForBurnWithCaller_returnsNonzeroNonce(
        address _mintRecipientAddr
    ) public {
        uint64 _nonce0 = localMessageTransmitter.sendMessage(
            remoteDomain,
            recipient,
            messageBody
        );
        assertEq(uint256(_nonce0), 0);

        uint64 _nonce1 = localMessageTransmitter.sendMessage(
            remoteDomain,
            recipient,
            messageBody
        );
        assertEq(uint256(_nonce1), 1);

        _depositForBurnWithCaller(_mintRecipientAddr, 5, destinationCaller);
    }

    function testDepositForBurnWithCaller_rejectsZeroDestinationCaller(
        uint256 _amount,
        uint32 _domain,
        bytes32 _mintRecipient,
        address _tokenAddress
    ) public {
        vm.expectRevert("Invalid destination caller");
        localTokenMessenger.depositForBurnWithCaller(
            _amount,
            _domain,
            _mintRecipient,
            _tokenAddress,
            emptyDestinationCaller
        );
    }

    function testDepositForBurnWithCaller_succeeds(uint256 _amount) public {
        vm.assume(_amount > 0);
        vm.assume(_amount <= mintAmount);

        address _mintRecipientAddr = vm.addr(1505);

        _depositForBurnWithCaller(
            _mintRecipientAddr,
            _amount,
            destinationCaller
        );
    }

    function testReplaceDepositForBurn_revertsForWrongSender(
        address _mintRecipientAddr,
        uint256 _amount,
        address _newDestinationCallerAddr
    ) public {
        address _newMintRecipientAddr = vm.addr(1802);
        bytes32 _mintRecipient = Message.addressToBytes32(_mintRecipientAddr);
        bytes32 localTokenAddressBytes32 = Message.addressToBytes32(
            address(localToken)
        );
        bytes memory _messageBody = BurnMessage._formatMessage(
            messageBodyVersion,
            localTokenAddressBytes32,
            _mintRecipient,
            _amount,
            Message.addressToBytes32(address(owner))
        );
        uint64 _nonce = localMessageTransmitter.availableNonces(remoteDomain);
        bytes memory _expectedMessage = Message._formatMessage(
            version,
            localDomain,
            remoteDomain,
            _nonce,
            Message.addressToBytes32(address(localTokenMessenger)),
            remoteTokenMessenger,
            emptyDestinationCaller,
            _messageBody
        );

        // attempt to replace message from wrong sender
        bytes32 _newDestinationCaller = Message.addressToBytes32(
            _newDestinationCallerAddr
        );
        bytes32 _newMintRecipient = Message.addressToBytes32(
            _newMintRecipientAddr
        );
        bytes memory _originalAttestation = bytes("mockAttestation");

        vm.prank(_newMintRecipientAddr);
        vm.expectRevert("Invalid sender for message");
        localTokenMessenger.replaceDepositForBurn(
            _expectedMessage,
            _originalAttestation,
            _newDestinationCaller,
            _newMintRecipient
        );
    }

    function testReplaceDepositForBurn_revertsInvalidAttestation(
        address _mintRecipientAddr,
        uint256 _amount,
        address _newDestinationCallerAddr,
        address _newMintRecipientAddr
    ) public {
        bytes32 _mintRecipient = Message.addressToBytes32(_mintRecipientAddr);
        bytes32 localTokenAddressBytes32 = Message.addressToBytes32(
            address(localToken)
        );
        bytes memory _messageBody = BurnMessage._formatMessage(
            messageBodyVersion,
            localTokenAddressBytes32,
            _mintRecipient,
            _amount,
            Message.addressToBytes32(address(owner))
        );
        uint64 _nonce = localMessageTransmitter.availableNonces(remoteDomain);
        bytes memory _expectedMessage = Message._formatMessage(
            version,
            localDomain,
            remoteDomain,
            _nonce,
            Message.addressToBytes32(address(localTokenMessenger)),
            remoteTokenMessenger,
            emptyDestinationCaller,
            _messageBody
        );

        // attempt to replace message from wrong sender
        bytes32 _newDestinationCaller = Message.addressToBytes32(
            _newDestinationCallerAddr
        );
        bytes32 _newMintRecipient = Message.addressToBytes32(
            _newMintRecipientAddr
        );
        bytes memory _originalAttestation = bytes("mockAttestation");

        vm.prank(owner);
        vm.expectRevert("Invalid attestation length");
        localTokenMessenger.replaceDepositForBurn(
            _expectedMessage,
            _originalAttestation,
            _newDestinationCaller,
            _newMintRecipient
        );
    }

    function testReplaceDepositForBurn_succeeds(
        uint64 _nonce,
        bytes32 _mintRecipient,
        address _newDestinationCallerAddr
    ) public {
        uint256 _amount = 5;

        bytes memory _expectedMessage = Message._formatMessage(
            version,
            localDomain,
            remoteDomain,
            _nonce,
            Message.addressToBytes32(address(localTokenMessenger)),
            remoteTokenMessenger,
            emptyDestinationCaller,
            BurnMessage._formatMessage(
                messageBodyVersion,
                Message.addressToBytes32(address(localToken)),
                _mintRecipient,
                _amount,
                Message.addressToBytes32(address(owner))
            )
        );

        bytes32 _newDestinationCaller = Message.addressToBytes32(
            _newDestinationCallerAddr
        );
        address _newMintRecipientAddr = vm.addr(1802);
        bytes32 _newMintRecipient = Message.addressToBytes32(
            _newMintRecipientAddr
        );
        uint256[] memory attesterPrivateKeys = new uint256[](1);
        attesterPrivateKeys[0] = attesterPK;
        bytes memory _signature = _signMessage(
            _expectedMessage,
            attesterPrivateKeys
        );

        // emits DepositForBurn
        vm.expectEmit(true, true, true, true);
        emit DepositForBurn(
            _nonce,
            address(localToken),
            _amount,
            owner,
            _newMintRecipient,
            remoteDomain,
            remoteTokenMessenger,
            _newDestinationCaller
        );

        vm.prank(owner);
        localTokenMessenger.replaceDepositForBurn(
            _expectedMessage,
            _signature,
            _newDestinationCaller,
            _newMintRecipient
        );
    }

    function testReplaceDepositForBurn_invalidMessage_revertsWithoutData(
        address _mintRecipientAddr,
        uint256 _amount,
        address _newDestinationCallerAddr,
        address _newMintRecipientAddr
    ) public {
        // attempt to replace message from wrong sender
        bytes32 _newDestinationCaller = Message.addressToBytes32(
            _newDestinationCallerAddr
        );
        bytes32 _newMintRecipient = Message.addressToBytes32(
            _newMintRecipientAddr
        );
        bytes memory _originalAttestation = bytes("mockAttestation");

        bytes memory _invalidMsg = "foo";

        vm.prank(owner);
        vm.expectRevert();
        localTokenMessenger.replaceDepositForBurn(
            _invalidMsg,
            _originalAttestation,
            _newDestinationCaller,
            _newMintRecipient
        );
    }

    function testHandleReceiveMessage_succeedsForMint(uint256 _amount) public {
        address _mintRecipientAddr = vm.addr(1505);
        vm.assume(_amount > 0);
        vm.assume(_amount <= mintAmount);

        bytes memory _messageBody = _depositForBurn(
            _mintRecipientAddr,
            _amount
        );

        // assert balance of recipient is initially 0
        assertEq(destToken.balanceOf(_mintRecipientAddr), 0);

        // test event is emitted
        vm.expectEmit(true, true, true, true);
        emit MintAndWithdraw(_mintRecipientAddr, _amount, address(destToken));

        vm.startPrank(address(remoteMessageTransmitter));
        assertTrue(
            destTokenMessenger.handleReceiveMessage(
                localDomain,
                Message.addressToBytes32(address(localTokenMessenger)),
                _messageBody
            )
        );
        vm.stopPrank();

        // assert balance of recipient is incremented by mint amount
        assertEq(destToken.balanceOf(_mintRecipientAddr), _amount);
    }

    function testHandleReceiveMessage_failsIfRecipientIsNotRemoteTokenMessenger()
        public
    {
        bytes memory _messageBody = bytes("foo");
        bytes32 _address = Message.addressToBytes32(address(vm.addr(1)));

        vm.startPrank(address(remoteMessageTransmitter));
        vm.expectRevert("Remote TokenMessenger unsupported");
        destTokenMessenger.handleReceiveMessage(
            localDomain,
            _address,
            _messageBody
        );

        vm.stopPrank();
    }

    function testHandleReceiveMessage_failsIfSenderIsNotLocalMessageTransmitter()
        public
    {
        bytes memory _messageBody = bytes("foo");
        bytes32 _address = Message.addressToBytes32(address(vm.addr(1)));

        vm.expectRevert("Invalid message transmitter");
        localTokenMessenger.handleReceiveMessage(
            localDomain,
            _address,
            _messageBody
        );
    }

    function testHandleReceiveMessage_revertsIfNoLocalMinterIsSet(
        bytes32 _mintRecipient,
        uint256 _amount
    ) public {
        bytes memory _messageBody = BurnMessage._formatMessage(
            messageBodyVersion,
            Message.addressToBytes32(address(localToken)),
            _mintRecipient,
            _amount,
            Message.addressToBytes32(address(remoteMessageTransmitter))
        );

        destTokenMessenger.removeLocalMinter();
        bytes32 _localTokenMessenger = Message.addressToBytes32(
            address(localTokenMessenger)
        );
        vm.startPrank(address(remoteMessageTransmitter));
        vm.expectRevert("Local minter is not set");
        destTokenMessenger.handleReceiveMessage(
            localDomain,
            _localTokenMessenger,
            _messageBody
        );
        vm.stopPrank();
    }

    function testHandleReceiveMessage_revertsIfNoEnabledLocalTokenSet(
        bytes32 _localToken,
        bytes32 _mintRecipient,
        uint256 _amount
    ) public {
        bytes memory _messageBody = BurnMessage._formatMessage(
            messageBodyVersion,
            _localToken,
            _mintRecipient,
            _amount,
            Message.addressToBytes32(address(remoteMessageTransmitter))
        );

        bytes32 _localTokenMessenger = Message.addressToBytes32(
            address(localTokenMessenger)
        );
        vm.startPrank(address(remoteMessageTransmitter));
        vm.expectRevert("Local token not enabled");
        destTokenMessenger.handleReceiveMessage(
            localDomain,
            _localTokenMessenger,
            _messageBody
        );
        vm.stopPrank();
    }

    function testHandleReceiveMessage_revertsOnInvalidMessage(uint256 _amount)
        public
    {
        vm.assume(_amount > 0);
        bytes32 _mintRecipient = Message.addressToBytes32(vm.addr(1505));

        bytes32 localTokenAddressBytes32 = Message.addressToBytes32(
            address(localToken)
        );

        // Format message body
        bytes memory _messageBody = abi.encodePacked(
            uint256(1),
            localTokenAddressBytes32,
            _mintRecipient,
            _amount
        );

        bytes32 _address = Message.addressToBytes32(address(vm.addr(1)));
        bytes32 _localTokenMessenger = Message.addressToBytes32(
            address(localTokenMessenger)
        );

        vm.startPrank(address(remoteMessageTransmitter));
        vm.expectRevert("Invalid message");
        destTokenMessenger.handleReceiveMessage(
            localDomain,
            _localTokenMessenger,
            _messageBody
        );
        vm.stopPrank();
    }

    function testAddRemoteTokenMessenger_succeeds(uint32 _domain) public {
        TokenMessenger _tokenMessenger = new TokenMessenger(
            address(localMessageTransmitter),
            messageBodyVersion
        );

        assertEq(_tokenMessenger.remoteTokenMessengers(_domain), bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit RemoteTokenMessengerAdded(_domain, remoteTokenMessenger);
        _tokenMessenger.addRemoteTokenMessenger(_domain, remoteTokenMessenger);

        assertEq(
            _tokenMessenger.remoteTokenMessengers(_domain),
            remoteTokenMessenger
        );
    }

    function testAddRemoteTokenMessenger_revertsOnExistingRemoteTokenMessenger()
        public
    {
        assertEq(
            localTokenMessenger.remoteTokenMessengers(remoteDomain),
            remoteTokenMessenger
        );

        vm.expectRevert("TokenMessenger already set");
        localTokenMessenger.addRemoteTokenMessenger(
            remoteDomain,
            remoteTokenMessenger
        );

        // original destination router is still registered
        assertEq(
            localTokenMessenger.remoteTokenMessengers(remoteDomain),
            remoteTokenMessenger
        );
    }

    function testAddRemoteTokenMessenger_revertsOnZeroAddress() public {
        vm.expectRevert("bytes32(0) not allowed");
        localTokenMessenger.addRemoteTokenMessenger(remoteDomain, bytes32(0));

        // original destination router is still registered
        assertEq(
            localTokenMessenger.remoteTokenMessengers(remoteDomain),
            remoteTokenMessenger
        );
    }

    function testAddRemoteTokenMessenger_revertsOnNonOwner(
        uint32 _domain,
        bytes32 _tokenMessenger
    ) public {
        expectRevertWithWrongOwner();
        localTokenMessenger.addRemoteTokenMessenger(_domain, _tokenMessenger);
    }

    function testRemoveRemoteTokenMessenger_succeeds() public {
        uint32 _remoteDomain = 100;
        bytes32 _remoteTokenMessenger = Message.addressToBytes32(vm.addr(1));

        localTokenMessenger.addRemoteTokenMessenger(
            _remoteDomain,
            _remoteTokenMessenger
        );

        vm.expectEmit(true, true, true, true);
        emit RemoteTokenMessengerRemoved(_remoteDomain, _remoteTokenMessenger);
        localTokenMessenger.removeRemoteTokenMessenger(
            _remoteDomain,
            _remoteTokenMessenger
        );
    }

    function testRemoveRemoteTokenMessenger_revertsOnNoTokenMessengerSet()
        public
    {
        uint32 _remoteDomain = 100;
        bytes32 _remoteTokenMessenger = Message.addressToBytes32(vm.addr(1));

        vm.expectRevert("No TokenMessenger set");
        localTokenMessenger.removeRemoteTokenMessenger(
            _remoteDomain,
            _remoteTokenMessenger
        );
    }

    function testRemoveRemoteTokenMessenger_revertsOnNonOwner(
        uint32 _domain,
        bytes32 _tokenMessenger
    ) public {
        expectRevertWithWrongOwner();
        localTokenMessenger.removeRemoteTokenMessenger(
            _domain,
            _tokenMessenger
        );
    }

    function testAddLocalMinter_succeeds(address _localMinter) public {
        vm.assume(_localMinter != address(0));
        TokenMessenger _tokenMessenger = new TokenMessenger(
            address(localMessageTransmitter),
            messageBodyVersion
        );
        _addLocalMinter(_localMinter, _tokenMessenger);
    }

    function testAddLocalMinter_revertsIfZeroAddress() public {
        vm.expectRevert("Zero address not allowed");
        localTokenMessenger.addLocalMinter(address(0));
    }

    function testAddLocalMinter_revertsIfAlreadySet(address _localMinter)
        public
    {
        vm.assume(_localMinter != address(0));
        vm.expectRevert("Local minter is already set.");
        localTokenMessenger.addLocalMinter(_localMinter);
    }

    function testAddLocalMinter_revertsOnNonOwner(address _localMinter) public {
        vm.assume(_localMinter != address(0));
        expectRevertWithWrongOwner();
        localTokenMessenger.addLocalMinter(_localMinter);
    }

    function testRemoveLocalMinter_succeeds() public {
        address _localMinter = vm.addr(1);
        TokenMessenger _tokenMessenger = new TokenMessenger(
            address(localMessageTransmitter),
            messageBodyVersion
        );
        _addLocalMinter(_localMinter, _tokenMessenger);

        vm.expectEmit(true, true, true, true);
        emit LocalMinterRemoved(_localMinter);
        _tokenMessenger.removeLocalMinter();
    }

    function testRemoveLocalMinter_revertsIfNoLocalMinterSet() public {
        TokenMessenger _tokenMessenger = new TokenMessenger(
            address(localMessageTransmitter),
            messageBodyVersion
        );
        vm.expectRevert("No local minter is set.");
        _tokenMessenger.removeLocalMinter();
    }

    function testRemoveLocalMinter_revertsOnNonOwner() public {
        expectRevertWithWrongOwner();
        localTokenMessenger.removeLocalMinter();
    }

    function testRescuable(
        address _rescuer,
        address _rescueRecipient,
        uint256 _amount
    ) public {
        assertContractIsRescuable(
            address(localTokenMessenger),
            _rescuer,
            _rescueRecipient,
            _amount
        );
    }

    function testTransferOwnership() public {
        address _newOwner = vm.addr(1509);
        transferOwnership(address(localTokenMessenger), _newOwner);
    }

    function _addLocalMinter(
        address _localMinter,
        TokenMessenger _tokenMessenger
    ) internal {
        vm.expectEmit(true, true, true, true);
        emit LocalMinterAdded(_localMinter);
        _tokenMessenger.addLocalMinter(_localMinter);
    }

    function _depositForBurn(
        address _mintRecipientAddr,
        uint256 _amount,
        uint256 _approveAmount,
        uint256 _mintAmount
    ) internal returns (bytes memory) {
        address _spender = address(localTokenMessenger);
        bytes32 _mintRecipient = Message.addressToBytes32(_mintRecipientAddr);

        localToken.mint(owner, _mintAmount);

        vm.prank(owner);
        localToken.approve(_spender, _approveAmount);

        bytes32 localTokenAddressBytes32 = Message.addressToBytes32(
            address(localToken)
        );

        bytes memory _messageBody = BurnMessage._formatMessage(
            messageBodyVersion,
            localTokenAddressBytes32,
            _mintRecipient,
            _amount,
            Message.addressToBytes32(address(owner))
        );

        uint64 _nonce = localMessageTransmitter.availableNonces(remoteDomain);

        bytes memory _expectedMessage = Message._formatMessage(
            version,
            localDomain,
            remoteDomain,
            _nonce,
            Message.addressToBytes32(address(localTokenMessenger)),
            remoteTokenMessenger,
            emptyDestinationCaller,
            _messageBody
        );

        vm.expectEmit(true, true, true, true);
        emit MessageSent(_expectedMessage);

        vm.expectEmit(true, true, true, true);
        emit DepositForBurn(
            _nonce,
            address(localToken),
            _amount,
            owner,
            _mintRecipient,
            remoteDomain,
            remoteTokenMessenger,
            emptyDestinationCaller
        );

        vm.prank(owner);
        uint64 _nonceReserved = localTokenMessenger.depositForBurn(
            _amount,
            remoteDomain,
            _mintRecipient,
            address(localToken)
        );

        assertEq(uint256(_nonce), uint256(_nonceReserved));

        bytes29 _m = _messageBody.ref(0);
        assertEq(
            _m._getBurnToken(),
            Message.addressToBytes32(address(localToken))
        );
        assertEq(_m._getMintRecipient(), _mintRecipient);
        assertEq(_m._getBurnToken(), localTokenAddressBytes32);
        assertEq(_m._getAmount(), _amount);

        return _messageBody;
    }

    function _depositForBurn(address _mintRecipientAddr, uint256 _amount)
        internal
        returns (bytes memory)
    {
        return
            _depositForBurn(
                _mintRecipientAddr,
                _amount,
                approveAmount,
                mintAmount
            );
    }

    function _depositForBurnWithCaller(
        address _mintRecipientAddr,
        uint256 _amount,
        bytes32 _destinationCaller,
        uint256 _approveAmount,
        uint256 _mintAmount
    ) internal returns (bytes memory) {
        bytes32 _mintRecipient = Message.addressToBytes32(_mintRecipientAddr);

        localToken.mint(owner, _mintAmount);

        vm.prank(owner);
        localToken.approve(address(localTokenMessenger), _approveAmount);

        // Format message body
        bytes memory _messageBody = BurnMessage._formatMessage(
            messageBodyVersion,
            Message.addressToBytes32(address(localToken)),
            _mintRecipient,
            _amount,
            Message.addressToBytes32(address(owner))
        );

        // assert that a MessageSent event was logged with expected message bytes
        uint64 _nonce = localMessageTransmitter.availableNonces(remoteDomain);

        bytes memory _expectedMessage = Message._formatMessage(
            version,
            localDomain,
            remoteDomain,
            _nonce,
            Message.addressToBytes32(address(localTokenMessenger)),
            remoteTokenMessenger,
            _destinationCaller,
            _messageBody
        );

        vm.expectEmit(true, true, true, true);
        emit MessageSent(_expectedMessage);

        vm.expectEmit(true, true, true, true);
        emit DepositForBurn(
            _nonce,
            address(localToken),
            _amount,
            owner,
            _mintRecipient,
            remoteDomain,
            remoteTokenMessenger,
            _destinationCaller
        );

        vm.prank(owner);
        uint64 _nonceReserved = localTokenMessenger.depositForBurnWithCaller(
            _amount,
            remoteDomain,
            _mintRecipient,
            address(localToken),
            _destinationCaller
        );

        assertEq(uint256(_nonce), uint256(_nonceReserved));

        // deserialize _messageBody
        bytes29 _m = _messageBody.ref(0);
        assertEq(
            _m._getBurnToken(),
            Message.addressToBytes32(address(localToken))
        );
        assertEq(_m._getMintRecipient(), _mintRecipient);
        assertEq(
            _m._getBurnToken(),
            Message.addressToBytes32(address(localToken))
        );
        assertEq(_m._getAmount(), _amount);

        return _messageBody;
    }

    function _depositForBurnWithCaller(
        address _mintRecipientAddr,
        uint256 _amount,
        bytes32 _destinationCaller
    ) internal returns (bytes memory) {
        return
            _depositForBurnWithCaller(
                _mintRecipientAddr,
                _amount,
                _destinationCaller,
                approveAmount,
                mintAmount
            );
    }
}