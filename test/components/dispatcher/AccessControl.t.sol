// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.4;

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
  RELINQUISH_OWNERSHIP_ID,
  CANCEL_OWNERSHIP_TRANSFER_ID
}                                     from "wormhole-sdk/components/dispatcher/Ids.sol";
import {BytesParsing}                 from "wormhole-sdk/libraries/BytesParsing.sol";
import {AdminsUpdated, NotAuthorized} from "wormhole-sdk/components/dispatcher/AccessControl.sol";
import {DispatcherTestBase}           from "./utils/DispatcherTestBase.sol";
import {
  checkForDuplicates, 
  existsInArray
} from "./utils/utils.sol";

contract AcessControlTest is DispatcherTestBase {
  using BytesParsing for bytes;

  address[] randomAddresses = [
    0x37cde30278f52BC9F8bC07E52C465057eAc6Bf96,
    0x424788562b875947856c721cfd238Ad702e6E815,
    0x6e7d92A67b230Eec23231CDfBf7016FE919a89fd,
    0x767f38969f1B66F2D453B41d07611544d7804cE6,
    0xfCd924a035eE5e56D17792049C4dc82af320EeE9,
    0x3f1BEDB7F4DfC2eb873A4616d46F9347E42DFC89,
    0x56B4DFf8Ba7f19BeCef7eD1aA09E610aA58F643e,
    0x385243ED9f2B433d570E0E23244C2E51Aa958A0e,
    0x1524B5138ca68a3f8D29d2C9B894Ef4d7939c905,
    0xb4dCDa5F1D5289C9BE755Fc98f10449300b93FcB,
    0x2C03EB37da90f0D509a26F7d3bA5fCaA1Bff0728,
    0x1CE448dd2F31cF491265D20A4798E1d8CE37dFd2,
    0xd3548c5f2B338c808caa30A58779810216Af3234,
    0xa4defcd1FFC497fEDB486A397F1b8f54a4a0768f,
    0xacd34EDCF516d15E3bB488d60CE88569B641a0E6
  ];

  address[] randomAddresses2 = [
    0xF81aC4660a6f9602993e44b63Bc7dA25293F35a0,
    0x08C32a86Fc2B4862cb1E35C0FfaA14372Bb43599,
    0x25619bc22F1d1Af01e7471a4f9491bfbbb036551,
    0x7Ae2d26B63a5CC90C0f4C7fbaC78b31DE06fD4b2,
    0x91dcd85b7ed157e8a1341D31eBb8Ea887E04EDe0,
    0x05E38af5E63625721F772D071958f18025A3A4BA,
    0xe8C583ce594Dc282943871E1cdD2ecb91751587e,
    0xd5016b563a3Fd7a0A87651585ea17C6669054c2B,
    0x1cf1AB7aaa60FE5944F0B52b28b66b421e568e99,
    0xc7c36d9DaF41348cB9815bA6947cac4AF4d8Ec30,
    0xC29768eAb16380d33564474E9D2464C25dda1815,
    0xC89f02A924D4eaAb5343082773B3800a45A18e19,
    0xF65A7A5A4bF3d6Ff45337C8749802eb22a07De03,
    0xa5FCD37E1Be05d5426ADeF1Df739f8E70c2Cb3B7,
    0x9C5d6a52b34B8bC8fEfFd5eD63f086554Bf124aD
  ];

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
    );
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

  function testCancelOwnershipTransfer_NotAuthorized(address newOwner) public {
    uint8 commandCount = 1;

    vm.prank(owner);
    dispatcher.transferOwnership(newOwner);

    vm.expectRevert(NotAuthorized.selector);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount, 
        CANCEL_OWNERSHIP_TRANSFER_ID
      )
    );
  }

  function testCancelOwnershipTransfer(address newOwner) public {
    uint8 commandCount = 1;

    vm.prank(owner);
    dispatcher.transferOwnership(newOwner);

    vm.prank(owner);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount, 
        CANCEL_OWNERSHIP_TRANSFER_ID
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

    bytes memory addAdminCommand = abi.encodePacked(
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

  function testDeepUpdateAdmin(
    uint8 addAdmins, 
    uint8 removeAdmins,
    uint8 secondAddAdmins
  ) public {
    uint maxAdmins = randomAddresses.length;
    addAdmins       = uint8(bound(addAdmins, 0, maxAdmins));
    removeAdmins    = uint8(bound(removeAdmins, 0, addAdmins));
    secondAddAdmins = uint8(bound(secondAddAdmins, 0, maxAdmins));

    // Get initial amount of admins
    uint8 commandCount = 1;
    (uint8 initialAdmins,) = invokeStaticDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_QUERIES_ID,
        commandCount, 
        ADMINS_ID
      )
    ).asUint8Unchecked(0);

    // Add first batch of admins
    commandCount = addAdmins;
    bytes memory addFirstAdmins = abi.encodePacked(
      ACCESS_CONTROL_ID,
      commandCount
    );
    bytes memory queryAdmins;

    for (uint i = 0; i < addAdmins; i++) {
      addFirstAdmins = abi.encodePacked(
        addFirstAdmins,
        ADD_ADMIN_ID,
        randomAddresses[i]
      );
      queryAdmins = abi.encodePacked(
        queryAdmins,
        IS_ADMIN_ID,
        randomAddresses[i]
      );
    }

    vm.prank(owner);
    invokeDispatcher(addFirstAdmins);

    // Query first batch of admins
    commandCount = addAdmins + 1;
    bytes memory areAdminsAndGetAdmins = abi.encodePacked(
      ACCESS_CONTROL_QUERIES_ID,
      commandCount, 
      ADMINS_ID,
      queryAdmins
    );

    bytes memory res = invokeStaticDispatcher(areAdminsAndGetAdmins);

    uint offset = 0;
    uint8 adminsCount;
    (adminsCount, offset) = res.asUint8Unchecked(offset);
    assertEq(adminsCount, addAdmins + initialAdmins);

    address admin_;
    (admin_, offset) = res.asAddressUnchecked(offset);
    assertEq(admin_, admin);

    for (uint i = 0; i < addAdmins; i++) {
      (admin_, offset) = res.asAddressUnchecked(offset);
      assertEq(admin_, randomAddresses[i]);
    }

    bool isAdmin;
    for (uint i = 0; i < addAdmins; i++) {
      (isAdmin, offset) = res.asBoolUnchecked(offset);
      assertEq(isAdmin, true);
    }

    // Remove some admins from the first batch of admins
    commandCount = removeAdmins;
    bytes memory removeAdmins_ = abi.encodePacked(
      ACCESS_CONTROL_ID,
      commandCount
    );
    for (uint i = 0; i < removeAdmins; i++) {
      removeAdmins_ = abi.encodePacked(
        removeAdmins_,
        REVOKE_ADMIN_ID,
        randomAddresses[i]
      );
    }

    vm.prank(owner);
    invokeDispatcher(removeAdmins_);

    // Query first batch of admins after removing some
    commandCount = addAdmins + 1;
    areAdminsAndGetAdmins = abi.encodePacked(
      ACCESS_CONTROL_QUERIES_ID,
      commandCount, 
      ADMINS_ID,
      queryAdmins
    );

    res = invokeStaticDispatcher(areAdminsAndGetAdmins);

    offset = 0;
    (adminsCount, offset) = res.asUint8Unchecked(offset);
    assertEq(adminsCount, addAdmins + initialAdmins - removeAdmins);

    address[] memory adminsArr = new address[](adminsCount);
    for (uint i = 0; i < adminsCount; i++) {
      (adminsArr[i], offset) = res.asAddressUnchecked(offset);
    }
    checkForDuplicates(adminsArr);

    existsInArray(adminsArr, admin);
    for (uint i = removeAdmins; i < addAdmins; i++) {
      assertTrue(existsInArray(adminsArr, randomAddresses[i]));
    }

    for (uint i = 0; i < addAdmins; i++) {
      (isAdmin, offset) = res.asBoolUnchecked(offset);
      assertEq(isAdmin, i >= removeAdmins);
    }

    // Add second batch of admins
    commandCount = secondAddAdmins;
    bytes memory addSecondAdmins = abi.encodePacked(
      ACCESS_CONTROL_ID,
      commandCount
    );
    queryAdmins = new bytes(0);
    for (uint i = 0; i < secondAddAdmins; i++) {
      addSecondAdmins = abi.encodePacked(
        addSecondAdmins,
        ADD_ADMIN_ID,
        randomAddresses2[i]
      );
      queryAdmins = abi.encodePacked(
        queryAdmins,
        IS_ADMIN_ID,
        randomAddresses2[i]
      );
    }

    vm.prank(owner);
    invokeDispatcher(addSecondAdmins);

    // Query second batch of admins
    commandCount = secondAddAdmins + 1;
    areAdminsAndGetAdmins = abi.encodePacked(
      ACCESS_CONTROL_QUERIES_ID,
      commandCount, 
      ADMINS_ID,
      queryAdmins
    );

    res = invokeStaticDispatcher(areAdminsAndGetAdmins);

    offset = 0;
    (adminsCount, offset) = res.asUint8Unchecked(offset);
    assertEq(adminsCount, addAdmins + secondAddAdmins + initialAdmins - removeAdmins);

    adminsArr = new address[](adminsCount);
    for (uint i = 0; i < adminsCount; i++) {
      (adminsArr[i], offset) = res.asAddressUnchecked(offset);
    }
    checkForDuplicates(adminsArr);

    existsInArray(adminsArr, admin);
    for (uint i = removeAdmins; i < addAdmins; i++) {
      assertTrue(existsInArray(adminsArr, randomAddresses[i]));
    }
    for (uint i = 0; i < secondAddAdmins; i++) {
      assertTrue(existsInArray(adminsArr, randomAddresses2[i]));
    }

    for (uint i = 0; i < secondAddAdmins; i++) {
      (isAdmin, offset) = res.asBoolUnchecked(offset);
      assertEq(isAdmin, true);
    }
  } 

  function testStaticUpdateAdmin() public {
    uint8 addAdmins   = 5;
    uint8 removeAdmins = 4;

    // Get initial amount of admins
    uint8 commandCount = 1;
    bytes memory res = invokeStaticDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_QUERIES_ID,
        commandCount, 
        ADMINS_ID
      )
    );

    uint offset = 0;
    uint8 adminsCount;
    address admin_;
    (adminsCount, offset) = res.asUint8Unchecked(offset);
    assertEq(adminsCount, 1);

    (admin_, ) = res.asAddressUnchecked(offset);
    assertEq(admin_, admin);

    // Add first batch of admins
    commandCount = addAdmins;
    bytes memory addFirstAdmins = abi.encodePacked(
      ACCESS_CONTROL_ID,
      commandCount
    );

    for (uint i = 0; i < addAdmins; i++) {
      addFirstAdmins = abi.encodePacked(
        addFirstAdmins,
        ADD_ADMIN_ID,
        randomAddresses[i]
      );
    }

    vm.prank(owner);
    invokeDispatcher(addFirstAdmins);

    // Query first batch of admins
    commandCount = 1;
    bytes memory getAdmins = abi.encodePacked(
      ACCESS_CONTROL_QUERIES_ID,
      commandCount, 
      ADMINS_ID
    );

    res = invokeStaticDispatcher(getAdmins);

    offset = 0;
    adminsCount;
    (adminsCount, offset) = res.asUint8Unchecked(offset);
    assertEq(adminsCount, 6);

    // Initial admin
    (admin_, offset) = res.asAddressUnchecked(offset);
    assertEq(admin_, admin);
    
    // New admins, randomAddresses[0] to randomAddresses[4]
    for (uint i = 0; i < addAdmins; i++) {
      (admin_, offset) = res.asAddressUnchecked(offset);
      assertEq(admin_, randomAddresses[i]);
    }

    // Remove some admins from the first batch of admins
    commandCount = removeAdmins;
    bytes memory removeAdmins_ = abi.encodePacked(
      ACCESS_CONTROL_ID,
      commandCount
    );
    for (uint i = 0; i < removeAdmins; i++) {
      removeAdmins_ = abi.encodePacked(
        removeAdmins_,
        REVOKE_ADMIN_ID,
        randomAddresses[i]
      );
    }

    vm.prank(owner);
    invokeDispatcher(removeAdmins_);

    // Query first batch of admins after removing some
    commandCount = 1;
    getAdmins = abi.encodePacked(
      ACCESS_CONTROL_QUERIES_ID,
      commandCount, 
      ADMINS_ID
    );

    res = invokeStaticDispatcher(getAdmins);

    offset = 0;
    (adminsCount, offset) = res.asUint8Unchecked(offset);
    assertEq(adminsCount, 2);

    // Initial admin
    (admin_, offset) = res.asAddressUnchecked(offset);
    assertEq(admin_, admin);
    
    // Last admin added, randomAddresses[4]
    (admin_, offset) = res.asAddressUnchecked(offset);
    assertEq(admin_, randomAddresses[4]);

    // Add one more admin
    commandCount = 1;
    vm.prank(owner);
    invokeDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_ID,
        commandCount,
        ADD_ADMIN_ID,
        randomAddresses2[0]
      )
    );

    // Query the final state
    commandCount = 1;
    getAdmins = abi.encodePacked(
      ACCESS_CONTROL_QUERIES_ID,
      commandCount, 
      ADMINS_ID
    );

    res = invokeStaticDispatcher(getAdmins);

    offset = 0;
    (adminsCount, offset) = res.asUint8Unchecked(offset);
    assertEq(adminsCount, 3);

    // Initial admin
    (admin_, offset) = res.asAddressUnchecked(offset);
    assertEq(admin_, admin);
    
    // randomAddresses[4]
    (admin_, offset) = res.asAddressUnchecked(offset);
    assertEq(admin_, randomAddresses[4]);

    // randomAddresses2[0]
    (admin_, offset) = res.asAddressUnchecked(offset);
    assertEq(admin_, randomAddresses2[0]);
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
      abi.encodeWithSelector(BytesParsing.LengthMismatch.selector, 3, 4)
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

    commandCount = 2;
    bytes memory res = invokeStaticDispatcher(
      abi.encodePacked(
        ACCESS_CONTROL_QUERIES_ID,
        commandCount,
        OWNER_ID,
        PENDING_OWNER_ID
      )
    );
    
    (address owner_, ) = res.asAddressUnchecked(0);
    (address pendingOwner_, ) = res.asAddressUnchecked(20);

    assertEq(owner_, address(0)); 
    assertEq(pendingOwner_, address(0));
  }
}
