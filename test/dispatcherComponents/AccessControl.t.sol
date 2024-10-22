// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

import { NotAuthorized } from "wormhole-sdk/dispatcherComponents/AccessControl.sol";
import { BytesParsing } from "wormhole-sdk/libraries/BytesParsing.sol";
import { DispatcherTestBase } from "./utils/DispatcherTestBase.sol";
import "wormhole-sdk/dispatcherComponents/ids.sol";

contract AcessControlTest is DispatcherTestBase {
  using BytesParsing for bytes;

  function testCompleteOwnershipTransfer(address newOwner) public {
    vm.assume(newOwner != address(this));
    uint8 commandCount = 1;

    vm.prank(owner);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector,
        ACCESS_CONTROL_ID,
        commandCount,
        PROPOSE_OWNERSHIP_TRANSFER_ID,
        newOwner
      )
    );

    commandCount = 2;
    bytes memory getRes = invokeStaticDispatcher(
      abi.encodePacked(
        dispatcher.get1959.selector,
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

    vm.prank(newOwner);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector, 
        ACQUIRE_OWNERSHIP_ID
      )
    );

    getRes = invokeStaticDispatcher(
      abi.encodePacked(
        dispatcher.get1959.selector,
        
        ACCESS_CONTROL_QUERIES_ID,
        commandCount,
        OWNER_ID,
        PENDING_OWNER_ID
      )
    );
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
        dispatcher.exec768.selector,
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
        dispatcher.exec768.selector,
        ACCESS_CONTROL_ID,
        commandCount,
        PROPOSE_OWNERSHIP_TRANSFER_ID,
        newOwner
      )
    );

    commandCount = 2;
    bytes memory getRes = invokeStaticDispatcher(
      abi.encodePacked(
        dispatcher.get1959.selector,
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
        dispatcher.exec768.selector, 
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
        dispatcher.exec768.selector,
        ACCESS_CONTROL_ID,
        commandCount,
        PROPOSE_OWNERSHIP_TRANSFER_ID,
        newOwner
      )
    );

    vm.prank(newOwner);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector, 
        ACQUIRE_OWNERSHIP_ID
      )
    );

    bytes memory getRes = invokeStaticDispatcher(
      abi.encodePacked(
        dispatcher.get1959.selector,
        
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
        dispatcher.get1959.selector,
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
        dispatcher.get1959.selector,
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
        dispatcher.get1959.selector,
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
        dispatcher.exec768.selector, 
        ACCESS_CONTROL_ID,
        commandCount, 
        PROPOSE_OWNERSHIP_TRANSFER_ID,
        newOwner
      )
    );

    vm.prank(newOwner);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector, 
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
        dispatcher.get1959.selector, 
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

    vm.expectRevert(NotAuthorized.selector);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector,
        ACCESS_CONTROL_ID,
        commandCount, 
        ADD_ADMIN_ID,
        newAdmin
      )
    );

    vm.expectRevert(NotAuthorized.selector);
    vm.prank(admin);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector,
        ACCESS_CONTROL_ID,
        commandCount, 
        ADD_ADMIN_ID,
        newAdmin
      )
    );
  } 

  function testAddAdmin(address newAdmin) public {
    vm.assume(newAdmin != admin);
    uint8 commandCount = 1;

    vm.prank(owner);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector,
        ACCESS_CONTROL_ID,
        commandCount, 
        ADD_ADMIN_ID,
        newAdmin
      )
    );

    commandCount = 2;
    bytes memory res = invokeStaticDispatcher(
      abi.encodePacked(
        dispatcher.get1959.selector,
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
        dispatcher.exec768.selector,
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
        dispatcher.exec768.selector,
        ACCESS_CONTROL_ID,
        commandCount, 
        ADD_ADMIN_ID,
        newAdmin
      )
    );

    commandCount = 1;
    vm.prank(admin);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector,
        ACCESS_CONTROL_ID,
        commandCount, 
        REVOKE_ADMIN_ID,
        newAdmin
      )
    );

    commandCount = 2;
    bytes memory res = invokeStaticDispatcher(
      abi.encodePacked(
        dispatcher.get1959.selector,
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

    vm.prank(admin);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector,
        ACCESS_CONTROL_ID,
        commandCount,
        REVOKE_ADMIN_ID,
        admin
      )
    );

    bool isAdmin;
    (isAdmin, ) = invokeStaticDispatcher(
      abi.encodePacked(
        dispatcher.get1959.selector,
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

    vm.expectRevert(NotAuthorized.selector);
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector,
        ACCESS_CONTROL_ID,
        commandCount,
        RELINQUISH_OWNERSHIP_ID
      )
    );
  }

  function testRelinquishOwnership_LengthMismatch() public {
    uint8 commandCount = 2;

    vm.prank(owner);
    vm.expectRevert(
      abi.encodeWithSelector(BytesParsing.LengthMismatch.selector, 4, 3)
    );
    invokeDispatcher(
      abi.encodePacked(
        dispatcher.exec768.selector,
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
        dispatcher.exec768.selector,
        ACCESS_CONTROL_ID,
        commandCount,
        RELINQUISH_OWNERSHIP_ID
      )
    );

    (address owner_, ) = invokeStaticDispatcher(
      abi.encodePacked(
        dispatcher.get1959.selector,
        ACCESS_CONTROL_QUERIES_ID,
        commandCount,
        OWNER_ID
      )
    ).asAddressUnchecked(0);

    assertEq(owner_, address(0));
  }
}
