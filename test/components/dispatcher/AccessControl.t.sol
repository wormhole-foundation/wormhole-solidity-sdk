// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import {BytesParsing}       from "wormhole-sdk/libraries/BytesParsing.sol";
import {AdminsUpdated, NotAuthorized}      from "wormhole-sdk/components/dispatcher/AccessControl.sol";
import {
  ACCESS_CONTROL_ID,
  ACCESS_CONTROL_QUERIES_ID,
  OWNER_ID,
  PENDING_OWNER_ID,
  ACQUIRE_OWNERSHIP_ID,
  IS_ADMIN_ID,
  ADMINS_ID,
  REVOKE_ADMIN_ID,
  ADD_ADMIN_ID,
  PROPOSE_OWNERSHIP_TRANSFER_ID,
  RELINQUISH_OWNERSHIP_ID
}                           from "wormhole-sdk/components/dispatcher/Ids.sol";
import {DispatcherTestBase} from "./utils/DispatcherTestBase.sol";

contract AcessControlTest is DispatcherTestBase {
  using BytesParsing for bytes;

  function testCompleteOwnershipTransfer(address newOwner) public {
    vm.assume(newOwner != address(this));
    uint8 commandCount = 1;

    vm.prank(owner);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount,
        PROPOSE_OWNERSHIP_TRANSFER_ID,
        newOwner
      )
    );

    commandCount = 2;
    bytes memory queries = abi.encodePacked(
      ACCESS_CONTROL_QUERIES_ID,
      commandCount,
      OWNER_ID,
      PENDING_OWNER_ID
    )
    bytes memory getRes = invokeStaticDispatcher(queries);
    (address owner_,        ) = getRes.asAddressUnchecked(0);
    (address pendingOwner_, ) = getRes.asAddressUnchecked(20);

    assertEq(owner_,        owner);
    assertEq(pendingOwner_, newOwner);

    vm.prank(newOwner);
    invokeDispatcher(
      abi.encodePacked(
        ACQUIRE_OWNERSHIP_ID
      )
    );

    getRes = invokeStaticDispatcher(queries);
    (owner_,        ) = getRes.asAddressUnchecked(0);
    (pendingOwner_, ) = getRes.asAddressUnchecked(20);

    assertEq(owner_, newOwner);
    assertEq(pendingOwner_, address(0));
  }

  function testOwnershipTransfer_NotAuthorized() public {
    uint8 commandCount = 1;
    address newOwner = makeAddr("newOwner");

    vm.expectRevert(NotAuthorized.selector);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount,
        PROPOSE_OWNERSHIP_TRANSFER_ID,
        newOwner
      )
    );
  }

  function testOwnershipTransfer() public {
    address newOwner = makeAddr("newOwner");
    uint8 commandCount = 1;

    vm.prank(owner);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount,
        PROPOSE_OWNERSHIP_TRANSFER_ID,
        newOwner
      )
    );

    commandCount = 2;
    bytes memory getRes = invokeStaticDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_QUERIES_ID,
        commandCount,
        OWNER_ID,
        PENDING_OWNER_ID
      )
    );
    (address owner_,        ) = getRes.asAddressUnchecked(0);
    (address pendingOwner_, ) = getRes.asAddressUnchecked(20);

    assertEq(owner_,        owner);
    assertEq(pendingOwner_, newOwner);
  }





  function testAcquireOwnership_NotAuthorized() public {
    vm.expectRevert(NotAuthorized.selector);
    invokeDispatcher(
      abi.encodePacked(
        ACQUIRE_OWNERSHIP_ID
      )
    );
  }

  function testAcquireOwnership() public {
    address newOwner = makeAddr("newOwner");
    uint8 commandCount = 1;

    vm.prank(owner);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount,
        PROPOSE_OWNERSHIP_TRANSFER_ID,
        newOwner
      )
    );

    vm.prank(newOwner);
    invokeDispatcher(
      abi.encodePacked(
        ACQUIRE_OWNERSHIP_ID
      )
    );

    bytes memory getRes = invokeStaticDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_QUERIES_ID,
        commandCount,
        OWNER_ID,
        PENDING_OWNER_ID
      )
    );
    (address owner_,        ) = getRes.asAddressUnchecked(0);
    (address pendingOwner_, ) = getRes.asAddressUnchecked(20);

    assertEq(owner_, newOwner);
    assertEq(pendingOwner_, address(0));
  }

  function testExternalOwnershipTransfer_NotAuthorized() public {
    address newOwner = makeAddr("newOwner");

    vm.expectRevert(NotAuthorized.selector);
    dispatcher.transferOwnership(newOwner);
  }

  function testExternalOwnershipTransfer(address newOwner) public {
    vm.prank(owner);
    dispatcher.transferOwnership(newOwner);

    uint8 commandCount = 2;
    bytes memory getRes = invokeStaticDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_QUERIES_ID,
        commandCount,
        OWNER_ID,
        PENDING_OWNER_ID
      )
    );
    (address owner_,        ) = getRes.asAddressUnchecked(0);
    (address pendingOwner_, ) = getRes.asAddressUnchecked(20);

    assertEq(owner_,        owner);
    assertEq(pendingOwner_, newOwner);
  }

  function testExternalCancelOwnershipTransfer_NotAuthorized() public {
    vm.expectRevert(NotAuthorized.selector);
    dispatcher.cancelOwnershipTransfer();
  }

  function testExternalCancelOwnershipTransfer(address newOwner) public {
    vm.prank(owner);
    dispatcher.transferOwnership(newOwner);

    vm.prank(owner);
    dispatcher.cancelOwnershipTransfer();

    uint8 commandCount = 2;
    bytes memory getRes = invokeStaticDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_QUERIES_ID,
        commandCount,
        OWNER_ID,
        PENDING_OWNER_ID
      )
    );
    (address owner_,        ) = getRes.asAddressUnchecked(0);
    (address pendingOwner_, ) = getRes.asAddressUnchecked(20);

    assertEq(owner_,        owner);
    assertEq(pendingOwner_, address(0));
  }

  function testExternalReceiveOwnership_NotAuthorized() public {
    vm.expectRevert(NotAuthorized.selector);
    dispatcher.receiveOwnership();
  }

  function testExternalReceiveOwnership(address newOwner) public {
    vm.prank(owner);
    dispatcher.transferOwnership(newOwner);

    vm.prank(newOwner);
    dispatcher.receiveOwnership();

    uint8 commandCount = 2;
    bytes memory getRes = invokeStaticDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_QUERIES_ID,
        commandCount,
        OWNER_ID,
        PENDING_OWNER_ID
      )
    );
    (address owner_,        ) = getRes.asAddressUnchecked(0);
    (address pendingOwner_, ) = getRes.asAddressUnchecked(20);

    assertEq(owner_, newOwner);
    assertEq(pendingOwner_, address(0));
  }

  function testBatchAfterAcquire(address newOwner, address newAdmin) public {
    vm.assume(newOwner != address(0));
    vm.assume(newOwner != owner);
    vm.assume(newAdmin != address(0));
    vm.assume(newAdmin != admin);
    uint8 commandCount = 1;

    vm.prank(owner);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount, 
        PROPOSE_OWNERSHIP_TRANSFER_ID,
        newOwner
      )
    );

    vm.prank(newOwner);
    invokeDispatcher(
      abi.encodePacked(
        ACQUIRE_OWNERSHIP_ID, 
        ACCESS_CONTROL_ID,
        commandCount, 
        ADD_ADMIN_ID,
        newAdmin
      )
    );

    commandCount = 3;
    bytes memory getRes = invokeStaticDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_QUERIES_ID,
        commandCount, 
        OWNER_ID,
        PENDING_OWNER_ID,
        IS_ADMIN_ID,
        newAdmin
      )
    );
    uint offset = 0;
    address owner_;
    address pendingOwner_;
    bool isAdmin;
    (owner_,        offset) = getRes.asAddressUnchecked(offset);
    (pendingOwner_, offset) = getRes.asAddressUnchecked(offset);
    (isAdmin,       offset) = getRes.asBoolUnchecked(offset);

    assertEq(owner_, newOwner);
    assertEq(pendingOwner_, address(0));
    assertEq(isAdmin, true);
  }

  function testAddAdmin_NotAuthorized() public {
    address newAdmin = makeAddr("newAdmin");
    uint8 commandCount = 1;

    bytes memory = addAdminCommand = abi.encodePacked(
      ACCESS_CONTROL_ID,
      commandCount,
      ADD_ADMIN_ID,
      newAdmin
    );

    vm.expectRevert(NotAuthorized.selector);
    invokeDispatcher(addAdminCommand);

    vm.expectRevert(NotAuthorized.selector);
    vm.prank(admin);
    invokeDispatcher(addAdminCommand);
  } 

  function testAddAdmin(address newAdmin) public {
    vm.assume(newAdmin != admin);
    uint8 commandCount = 1;

    vm.expectEmit();
    emit AdminsUpdated(newAdmin, true, block.timestamp);
    vm.prank(owner);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount, 
        ADD_ADMIN_ID,
        newAdmin
      )
    );

    commandCount = 2;
    bytes memory res = invokeStaticDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_QUERIES_ID,
        commandCount,
        IS_ADMIN_ID,
        newAdmin,
        ADMINS_ID
      )
    );
    
    (bool isAdmin, ) = res.asBoolUnchecked(0);
    (uint8 adminsCount, ) = res.asUint8Unchecked(1);
    (address newAdmin_, ) = res.asAddressUnchecked(res.length - 20);

    assertEq(isAdmin, true);
    assertEq(adminsCount, 2);
    assertEq(newAdmin_, newAdmin);
  } 

  function testRevokeAdmin_NotAuthorized() public {
    address newAdmin = makeAddr("newAdmin");
    uint8 commandCount = 1;

    vm.expectRevert(NotAuthorized.selector);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount, 
        REVOKE_ADMIN_ID,
        newAdmin
      )
    );
  } 

  function testRevokeAdmin(address newAdmin) public {
    vm.assume(newAdmin != admin);
    uint8 commandCount = 1;

    vm.prank(owner);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount, 
        ADD_ADMIN_ID,
        newAdmin
      )
    );

    commandCount = 1;

    vm.expectEmit();
    emit AdminsUpdated(newAdmin, false, block.timestamp);

    vm.prank(admin);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount, 
        REVOKE_ADMIN_ID,
        newAdmin
      )
    );

    commandCount = 2;
    bytes memory res = invokeStaticDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_QUERIES_ID,
        commandCount,
        IS_ADMIN_ID,
        newAdmin,
        ADMINS_ID
      )
    );
    
    (bool isAdmin, ) = res.asBoolUnchecked(0);
    (uint8 adminsCount, ) = res.asUint8Unchecked(1);

    assertEq(isAdmin, false);
    assertEq(adminsCount, 1);
  } 

  function testRelinquishAdministration() public {
    uint8 commandCount = 1;

    vm.expectEmit();
    emit AdminsUpdated(admin, false, block.timestamp);

    vm.prank(admin);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount,
        REVOKE_ADMIN_ID,
        admin
      )
    );

    bool isAdmin;
    (isAdmin, ) = invokeStaticDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_QUERIES_ID,
        commandCount,
        IS_ADMIN_ID,
        admin
      )
    ).asBoolUnchecked(0);

    assertEq(isAdmin, false);
  }

  function testRelinquishOwnership_NotAuthorized() public {
    uint8 commandCount = 1;
    bytes memory relinquishCommand = abi.encodePacked(
      ACCESS_CONTROL_ID,
      commandCount,
      RELINQUISH_OWNERSHIP_ID
    );

    vm.expectRevert(NotAuthorized.selector);
    invokeDispatcher(relinquishCommand);


    vm.expectRevert(NotAuthorized.selector);
    vm.prank(admin);
    invokeDispatcher(relinquishCommand);
  }

  function testRelinquishOwnership_LengthMismatch() public {
    uint8 commandCount = 2;

    vm.prank(owner);
    vm.expectRevert(
      abi.encodeWithSelector(BytesParsing.LengthMismatch.selector, 4, 3)
    );
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount,
        RELINQUISH_OWNERSHIP_ID,
        ADD_ADMIN_ID
      )
    );
  }


  function testRelinquishOwnership() public {
    uint8 commandCount = 1;

    vm.prank(owner);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount,
        RELINQUISH_OWNERSHIP_ID
      )
    );

    (address owner_, ) = invokeStaticDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_QUERIES_ID,
        commandCount,
        OWNER_ID
      )
    ).asAddressUnchecked(0);

    assertEq(owner_, address(0));
  }
}
