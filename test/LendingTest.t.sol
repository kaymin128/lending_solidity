// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../src/DreamAcademyLending.sol";

contract CUSDC is ERC20 {// USDC라는 스테이블 코인을 시뮬레이션하는 ERC20 토큰 컨트랙트
    constructor() ERC20("Circle Stable Coin", "USDC") {
        _mint(msg.sender, type(uint256).max);
    }
}

contract DreamOracle {// 토큰 가격을 제공하는 오라클 컨트랙트
// 특정 토큰의 가격을 설정하고 그 가격을 조회할 수 있게 해줌
    address public operator;
    mapping(address => uint256) prices;

    constructor() {
        operator = msg.sender;
    }

    function getPrice(address token) external view returns (uint256) {
        require(prices[token] != 0, "the price cannot be zero");
        return prices[token];
    }

    function setPrice(address token, uint256 price) external {
        require(msg.sender == operator, "only operator can set the price");
        prices[token] = price;
    }
}

contract Testx is Test {// 시뮬레이션 컨트랙트
    DreamOracle dreamOracle;
    DreamAcademyLending lending;
    ERC20 usdc;

    address user1;
    address user2;
    address user3;
    address user4;

    function setUp() external {// 테스트 환경을 초기화하는 함수. 오라클, 대출 컨트랙트, USDC 토큰 등을 초기화하고 필요한 기본 설정을 수행함
        user1 = address(0x1337);
        user2 = address(0x1337 + 1);
        user3 = address(0x1337 + 2);
        user4 = address(0x1337 + 3);
        dreamOracle = new DreamOracle();

        vm.deal(address(this), 10000000 ether);
        usdc = new CUSDC();
        // TDOO 아래 setUp이 정상작동 할 수 있도록 여러분의 Lending Contract를 수정하세요.
        lending = new DreamAcademyLending(IPriceOracle(address(dreamOracle)), address(usdc));
        usdc.approve(address(lending), type(uint256).max);

        lending.initializeLendingProtocol{value: 1}(address(usdc)); // set reserve ^__^

        dreamOracle.setPrice(address(0x0), 1339 ether);
        dreamOracle.setPrice(address(usdc), 1 ether);
    }

    function testDepositEtherWithoutTxValueFails() external {
        // 트랜잭션에 이더가 첨부되지 않았을때 입금 실패하는지 확인
        (bool success,) = address(lending).call{value: 0 ether}(
            abi.encodeWithSelector(DreamAcademyLending.deposit.selector, address(0x0), 1 ether)
        );
        assertFalse(success);
    }

    function testDepositEtherWithInsufficientValueFails() external {
        // 첨부된 이더가 요청한 입금액보다 적을 때 입금이 실패하는지 확인
        (bool success,) = address(lending).call{value: 2 ether}(
            abi.encodeWithSelector(DreamAcademyLending.deposit.selector, address(0x0), 3 ether)
        );
        assertFalse(success);
    }

    function testDepositEtherWithEqualValueSucceeds() external {
        // 첨부된 이더가 요청한 입금액과 동일할 때 입금이 성공하는지 확인
        (bool success,) = address(lending).call{value: 2 ether}(
            abi.encodeWithSelector(DreamAcademyLending.deposit.selector, address(0x0), 2 ether)
        );
        assertTrue(success);
        assertTrue(address(lending).balance == 2 ether + 1);
    }

    function testDepositUSDCWithInsufficientValueFails() external {
        // 승인된 USDC 양이 요청한 입금액보다 적을 때 입금이 실패하는지 확인
        usdc.approve(address(lending), 1);
        (bool success,) = address(lending).call(
            abi.encodeWithSelector(DreamAcademyLending.deposit.selector, address(usdc), 3000 ether)
        );
        assertFalse(success);
    }

    function testDepositUSDCWithEqualValueSucceeds() external {
        // 승인된 USDC양이 요청한 입금액과 동일할 때 입금이 성공하는지 확인
        (bool success,) = address(lending).call(
            abi.encodeWithSelector(DreamAcademyLending.deposit.selector, address(usdc), 2000 ether)
        );
        assertTrue(success);
        assertTrue(usdc.balanceOf(address(lending)) == 2000 ether + 1);
    }

    function supplyUSDCDepositUser1() private {
        // user1이 대규모 USDC를 대출 프로토콜에 입금하는 함수. 이후 테스트에서 사용할 수 있게 user1의 자산을 준비함
        usdc.transfer(user1, 100000000 ether);
        vm.startPrank(user1);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 100000000 ether);
        vm.stopPrank();
    }

    function supplyEtherDepositUser2() private {
        // user2가 대규모 이더를 대출 프로토콜에 입금함.
        vm.deal(user2, 100000000 ether);
        vm.prank(user2);
        lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);
    }

    function supplySmallEtherDepositUser2() private {
        // user2가 소량의 이더를 대출 프로토콜에 입금함. 담보가 충분하지 않은 시나리오에서 사용됨.
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        lending.deposit{value: 1 ether}(address(0x00), 1 ether);
        vm.stopPrank();
    }

    function testBorrowWithInsufficientCollateralFails() external {
        // 담보가 부족할 때 대출이 실패하는지 확인.
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 1339 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertFalse(success);
            assertTrue(usdc.balanceOf(user2) == 0 ether);
        }
        vm.stopPrank();
    }

    function testBorrowWithInsufficientSupplyFails() external {
        // 대출 요청량이 공급된 자산보다 많을 때 대출이 실패하는지 확인
        supplySmallEtherDepositUser2();
        dreamOracle.setPrice(address(0x0), 99999999999 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertFalse(success);
            assertTrue(usdc.balanceOf(user2) == 0 ether);
        }
        vm.stopPrank();
    }

    function testBorrowWithSufficientCollateralSucceeds() external {
        // 충분한 담보가 있을 때 대출이 성공하는지 확인
        supplyUSDCDepositUser1();
        supplyEtherDepositUser2();

        vm.startPrank(user2);
        {
            lending.borrow(address(usdc), 1000 ether);
            assertTrue(usdc.balanceOf(user2) == 1000 ether);
        }
        vm.stopPrank();
    }

    function testBorrowWithSufficientSupplySucceeds() external {
        // 충분한 공급이 있을 때 대출이 성공하는지 확인
        supplyUSDCDepositUser1();
        supplyEtherDepositUser2();

        vm.startPrank(user2);
        {
            lending.borrow(address(usdc), 1000 ether);
        }
        vm.stopPrank();
    }

    function testBorrowMultipleWithInsufficientCollateralFails() external {
        // 담보가 부족한 상태에서 여러 번 대출 시도가 실패하는지 확인
        supplyUSDCDepositUser1();
        // user1이 대량의 USDC를 예치함
        supplySmallEtherDepositUser2();
        // user2가 1 이더를 예치함, 담보가 충분하지 않은 상태로 설정
        dreamOracle.setPrice(address(0x0), 3000 ether);
        // 오라클에서 1 이더를 3000 으로 가격을 설정
        // 총 3000원이 있는거임
        // 1 USDC는 1임

        vm.startPrank(user2);// user2의 트랜잭션을 시뮬레이션 시작
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            // user2가 1000 이더 가치의 USDC를 대출하려 시도
            assertTrue(success);
            // 첫번째 대출이 성공했는지 확인
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            //user2가 동일한 금액의 USDC를 다시 대출하려 시도
            assertFalse(success);
            // 두번째 대출이 실패했는지 확인 (담보 부족으로 실패해야 함)
            assertTrue(usdc.balanceOf(user2) == 1000 ether);
            // user2가 실제로 첫번째 대출에서 1000 이더 가치의 USDC를 받았는지 확인
        }
        vm.stopPrank();
        // user2의 트랜잭션 시뮬레이션 종료
    }

    function testBorrowMultipleWithSufficientCollateralSucceeds() external {
        // 충분한 담보가 있을 때 여러 번 대출 시도가 성공하는지 확인
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);
        }
        vm.stopPrank();
    }

    function testBorrowWithSufficientCollateralAfterRepaymentSucceeds() external {
        // 상환 후 충분한 담보가 있을 때 대출이 다시 성공하는지 확인
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.repay.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testBorrowWithInSufficientCollateralAfterRepaymentFails() external {
        // 상환 후 담보가 부족할 때 대출이 실패하는지 확인
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);

            vm.roll(block.number + 1);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.repay.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertFalse(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 999 ether)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testWithdrawInsufficientBalanceFails() external {
        // 잔액보다 많은 금액을 인출하려 할 때 인출이 실패하는지 확인
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);

            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 100000001 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testWithdrawUnlockedBalanceSucceeds() external {
        // 잠기지 않은 잔액을 인출할 때 인출이 성공하는지 확인
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);

            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 100000001 ether - 1 ether)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testWithdrawMultipleUnlockedBalanceSucceeds() external {
        // 여러 번 잠기지 않은 잔액을 인출할 때 모두 성공하는지 확인
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);

            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 100000000 ether / 4)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 100000000 ether / 4)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 100000000 ether / 4)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 100000000 ether / 4)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testWithdrawLockedCollateralFails() external {
        // 대출 후 담보로 잠긴 자산을 인출하려 할 때 인출이 실패하는지 확인
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 1 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testWithdrawLockedCollateralAfterBorrowSucceeds() external {
        // 대출 후 특정 조건 하에 담보로 잠긴 일부 자산을 인출할 때 성공하는지 확인
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether); // 4000 usdc

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            // 2000 / (4000 - 1333) * 100 = 74.xxxx
            // LT = 75%
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 1 ether * 1333 / 4000)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testWithdrawLockedCollateralAfterInterestAccuredFails() external {
        // 이자가 발생한 후 담보로 잠긴 자산을 인출하려 할 때 인출이 실패하는지 확인
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether); // 4000 usdc

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            // 2000 / (4000 - 1333) * 100 = 74.xxxx
            // LT = 75%
            vm.roll(block.number + 1000);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 1 ether * 1333 / 4000)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testWithdrawYieldSucceeds() external {
        // 발생한 이자를 인출할 때 성공하는지 확인
        usdc.transfer(user3, 30000000 ether);
        vm.startPrank(user3);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 30000000 ether);
        vm.stopPrank();

        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        bool success;

        vm.startPrank(user2);
        {
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 1 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();

        vm.roll(block.number + (86400 * 1000 / 12));
        vm.prank(user3);
        assertTrue(lending.getAccruedSupplyAmount(address(usdc)) / 1e18 == 30000792);

        vm.roll(block.number + (86400 * 500 / 12));
        vm.prank(user3);
        assertTrue(lending.getAccruedSupplyAmount(address(usdc)) / 1e18 == 30001605);

        vm.prank(user3);
        (success,) = address(lending).call(
            abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(usdc), 30001605 ether)
        );
        assertTrue(success);
        assertTrue(usdc.balanceOf(user3) == 30001605 ether);

        assertTrue(lending.getAccruedSupplyAmount(address(usdc)) / 1e18 == 0);
    }

    function testExchangeRateChangeAfterUserBorrows() external {
        // 대출 후 이자율 변경에 따른 사용자 잔액 변화를 확인
        usdc.transfer(user3, 30000000 ether);
        vm.startPrank(user3);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 30000000 ether);
        //user3이 3000만 USDC를 예치한다
        vm.stopPrank();

        supplyUSDCDepositUser1();// user1이 대량의 USDC를 예치
        supplySmallEtherDepositUser2();// user2가 1 이더를 예치

        dreamOracle.setPrice(address(0x0), 4000 ether);// 1이더가 4000원
        // 1 USDC는 1원
        vm.startPrank(user2);// 여기서부터 user2
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );// user2가 1000 USDC를 빌리면 (1000원)
            assertTrue(success);// 성공

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );// user2가 1000 USDC를 더 빌려도 (1000원)
            assertTrue(success);// 성공

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 1 ether)
            );// user2가 1이더를 인출하려하면
            assertFalse(success);// 실패
        }
        vm.stopPrank();

        vm.roll(block.number + (86400 * 1000 / 12));// 1000일이 지났다 !
        vm.prank(user3);// 난 user3이다
        assertTrue(lending.getAccruedSupplyAmount(address(usdc)) / 1e18 == 30000792);// 여기서 문제가 남
        
        // other lender deposits USDC to our protocol.
        usdc.transfer(user4, 10000000 ether);
        vm.startPrank(user4);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 10000000 ether);
        vm.stopPrank();

        vm.roll(block.number + (86400 * 500 / 12));
        vm.prank(user3);
        uint256 a = lending.getAccruedSupplyAmount(address(usdc));

        vm.prank(user4);
        uint256 b = lending.getAccruedSupplyAmount(address(usdc));

        vm.prank(user1);
        uint256 c = lending.getAccruedSupplyAmount(address(usdc));

        assertEq((a + b + c) / 1e18 - 30000000 - 10000000 - 100000000, 6956);
        assertEq(a / 1e18 - 30000000, 1547);
        assertEq(b / 1e18 - 10000000, 251);
    }

    function testWithdrawFullUndilutedAfterDepositByOtherAccountSucceeds() external {
        // 다른 사용자가 입금한 후에도 초기 사용자가 잔액을 전액 인출할 수 있는지 확인
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);
        }
        vm.stopPrank();

        vm.deal(user3, 100000000 ether);
        vm.startPrank(user3);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);
        }
        vm.stopPrank();

        vm.startPrank(user2);
        {
            lending.withdraw(address(0x00), 100000000 ether);
            assertEq(address(user2).balance, 100000000 ether);
        }
        vm.stopPrank();
    }

    function testLiquidationHealthyLoanFails() external {
        // 담보가 충분한 대출을 청산하려 할 때 실패하는지 확인
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        usdc.transfer(user3, 3000 ether);
        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 800 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testLiquidationUnhealthyLoanSucceeds() external {
        // 담보가 부족한 대출을 성공적으로 청산할 수 있는지 확인
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        dreamOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop price to 66%
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 500 ether)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testLiquidationExceedingDebtFails() external {
        // 청산하려는 금액이 빚을 초과할 때 청산이 실패하는지 확인

        // ** README **
        // can liquidate the whole position when the borrowed amount is less than 100,
        // otherwise only 25% can be liquidated at once.
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        dreamOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop price to 66%
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 501 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testLiquidationHealthyLoanAfterPriorLiquidationFails() external {
        // 이전 청산 후 건강한 대출을 다시 청산하려 할 때 실패하는지 확인
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        dreamOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop price to 66%
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 500 ether)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 100 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testLiquidationAfterBorrowerCollateralDepositFails() external {
        // 담보가 다시 입금된 후에도 청산이 실패하는지 확인
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop price to 66%
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 500 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testLiquidationAfterDebtPriceDropFails() external {
        // 빚의 가격이 떨어진 후에도 청산이 실패하는지 확인

        // just imagine if USDC falls down
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        dreamOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop Ether price to 66%
        dreamOracle.setPrice(address(usdc), 1e17); // drop USDC price to 0.1, 90% down
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 500 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    receive() external payable {
        // for ether receive
    }
}