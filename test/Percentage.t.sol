// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import {Percentage, PercentageLib} from "wormhole-sdk/libraries/Percentage.sol";

contract TypeLibsTest is Test {
  function testPercentageFixed() public {
    Percentage pi = PercentageLib.to(3141, 3);
    assertEq(pi.mulUnchecked(1e0), 0);
    assertEq(pi.mulUnchecked(1e1), 0);
    assertEq(pi.mulUnchecked(1e2), 3);
    assertEq(pi.mulUnchecked(1e3), 31);
    assertEq(pi.mulUnchecked(1e4), 314);
    assertEq(pi.mulUnchecked(1e5), 3141);

    assertEq(PercentageLib.to(3141, 4).mulUnchecked(1e6), 3141);
  }

  function testPercentageDigit() public {
    for (uint digit = 0; digit < 10; ++digit) {
      assertEq(PercentageLib.to(digit * 100, 0).mulUnchecked(1e0), digit);
      assertEq(PercentageLib.to(digit *  10, 0).mulUnchecked(1e1), digit);
      assertEq(PercentageLib.to(digit      , 0).mulUnchecked(1e2), digit);
      assertEq(PercentageLib.to(digit      , 1).mulUnchecked(1e3), digit);
      assertEq(PercentageLib.to(digit      , 2).mulUnchecked(1e4), digit);
      assertEq(PercentageLib.to(digit      , 3).mulUnchecked(1e5), digit);
      assertEq(PercentageLib.to(digit      , 4).mulUnchecked(1e6), digit);
    }
  }

  function testPercentageFuzz(uint value, uint rngSeed_) public {
    uint[] memory rngSeed = new uint[](1);
    rngSeed[0] = rngSeed_;
    vm.assume(value < type(uint256).max/1e4);
    Percentage percentage = fuzzPercentage(rngSeed);
    uint unwrapped   = Percentage.unwrap(percentage);
    uint mantissa    = unwrapped >> 2;
    uint fractDigits = (unwrapped & 3) + 1;
    uint denominator = 10**(fractDigits + 2); //+2 to adjust for percentage to floating point conv
    assertEq(percentage.mulUnchecked(value), value * mantissa / denominator);
  }

  function nextRn(uint[] memory rngSeed) private pure returns (uint) {
    rngSeed[0] = uint(keccak256(abi.encode(rngSeed[0])));
    return rngSeed[0];
  }

  function fuzzPercentage(uint[] memory rngSeed) private pure returns (Percentage) {
    uint fractionalDigits = uint8(nextRn(rngSeed) % 5); //at most 4 fractional digits
    uint mantissa         = uint16(nextRn(rngSeed) >> 8) % 1e4; //4 digit mantissa

    if (mantissa > 100 && fractionalDigits == 0)
      ++fractionalDigits;
    if (mantissa > 1000 && fractionalDigits < 2)
      ++fractionalDigits;

    return PercentageLib.to(mantissa, fractionalDigits);
  }
}
