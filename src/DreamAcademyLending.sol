// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/forge-std/src/console.sol";
import "../test/LendingTest.t.sol";


interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
}

contract DreamAcademyLending {
    Testx test;
    IPriceOracle public oracle; 
    IERC20 public usdc; 
    uint256 public block_time = 12;


    uint256 public annual_interest_rate = 5; 
    uint256 public seconds_per_year = 365 * 24 * 60 * 60; 

    struct User {
        uint256 deposited_ether; 
        uint256 deposited_usdc; 
        uint256 borrowed_usdc; 
        uint256 last_interest_block; 
        uint256 total_supply;
    }

    uint256 public total_supply; 
    uint256 public total_borrowed; 

    mapping(address => User) public users; 

    constructor(IPriceOracle _oracle, address _usdc) {
        oracle = _oracle;
        usdc = IERC20(_usdc);
    }

    function initializeLendingProtocol(address token) external payable {
        require(msg.value == 1, "value has to be 1");
        usdc.transferFrom(msg.sender, address(this), msg.value);
    }

    function deposit(address token, uint256 amount) public payable {
        if (token == address(0x0)) { // eth
            require(msg.value == amount, "incorrect ether amount");
            users[msg.sender].deposited_ether += amount;
            users[msg.sender].total_supply += amount * oracle.getPrice(address(0x0));
            total_supply += amount * oracle.getPrice(address(0x0));
        } 
        else { // USDC
            require(usdc.balanceOf(msg.sender)>=amount, "insufficient USDC");
            require(usdc.transferFrom(msg.sender, address(this), amount), "USDC transfer failed");
            users[msg.sender].deposited_usdc += amount;
            users[address(msg.sender)].total_supply += amount * oracle.getPrice(address(usdc));
            total_supply += amount * oracle.getPrice(address(usdc));
            
        } 
    }
    function repay(address token, uint256 amount) external {
        require(token == address(usdc), "only USDC !!");

        _updateInterest(msg.sender);
        require(amount <= users[msg.sender].borrowed_usdc, "repay amount bigger than debt");

        require(usdc.transferFrom(msg.sender, address(this), amount), "USDC transfer failed");

        users[msg.sender].borrowed_usdc -= amount;
        total_borrowed -= amount;
        total_supply += amount;
    }
    function borrow(address token, uint256 amount) external {
        require(token == address(usdc), "only USDC can be borrowed");

        _updateInterest(msg.sender); 
        uint256 ether_collateral_value = users[msg.sender].deposited_ether * oracle.getPrice(address(0x0));
        uint256 usdc_collateral_value = users[msg.sender].deposited_usdc * oracle.getPrice(address(usdc));
        uint256 total_collateral = ether_collateral_value + usdc_collateral_value;
        uint256 borrowed=users[msg.sender].borrowed_usdc*oracle.getPrice(address(usdc));
        uint256 max=total_collateral*50/100-borrowed;
        require(max>=amount*oracle.getPrice(token), "not enough collateral");
        require(total_supply >= amount, "not enough liquidity in the protocol");

        users[msg.sender].borrowed_usdc += amount;
        total_borrowed += amount;
        total_supply -= amount;

        require(usdc.transfer(msg.sender, amount), "USDC transfer failed");
    }

    function withdraw(address token, uint256 amount) external {
        _updateInterest(msg.sender); 
        uint256 ether_collateral_value = users[msg.sender].deposited_ether * oracle.getPrice(address(0x0));
        uint256 usdc_collateral_value = users[msg.sender].deposited_usdc * oracle.getPrice(address(usdc));
        uint256 borrowed=users[msg.sender].borrowed_usdc*oracle.getPrice(address(usdc));
        uint256 total_collateral = ether_collateral_value + usdc_collateral_value;
        uint256 withdraw=amount*oracle.getPrice(token);
        uint256 max=total_collateral-borrowed;
        require(max>=withdraw, "not enough balance");

        uint256 left_collateral=max+borrowed-withdraw;
        require(left_collateral*75/100>=borrowed, "not enough collateral");
        if (token == address(0x0)) { 
            require(users[msg.sender].deposited_ether >= amount, "not enough balance");
            users[msg.sender].deposited_ether -= amount;
            total_supply -= amount;
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ether transfer failed");
        } 
        else { 
            require(users[msg.sender].deposited_usdc >= amount, "not enough balance");
            users[msg.sender].deposited_usdc -= amount;
            total_supply -= amount;
            require(usdc.transfer(msg.sender, amount), "USDC transfer failed");
        } 
    }

    function liquidate(address user, address token, uint256 amount) external {
        require(token == address(usdc), "Only USDC !!");

        _updateInterest(user); 
        uint max_liquidation=users[user].borrowed_usdc/4;
        require(amount<=max_liquidation, "borrowed amount is too small");
        uint256 ether_collateral_value = users[user].deposited_ether * oracle.getPrice(address(0x0));
        uint256 user_debt = users[user].borrowed_usdc*oracle.getPrice(token);

        require(ether_collateral_value * 75 / 100 < user_debt, "enough collateral !");
        users[user].borrowed_usdc -= amount;
        total_borrowed -= amount;

        uint256 reward_ether = amount / oracle.getPrice(address(0x0));
        users[user].deposited_ether -= reward_ether;

        (bool success, ) = msg.sender.call{value: reward_ether}("");
        require(success, "ether transfer failed");
    }

    function _updateInterest(address user) internal {
        uint256 last_block = users[user].last_interest_block;

        uint256 blocks_passed = block.number - last_block; 
        uint256 interest_rate_per_block = (annual_interest_rate * 1e18) / (seconds_per_year / block_time);

        uint256 accrued_interest = (users[user].borrowed_usdc * interest_rate_per_block * blocks_passed) / 1e18;
        users[user].borrowed_usdc += accrued_interest;

        uint256 supply_interest = (users[user].total_supply * interest_rate_per_block * blocks_passed) / 1e18;
        users[user].total_supply += supply_interest;
        users[user].last_interest_block = block.number; 
    }

    function getAccruedSupplyAmount(address token) external returns (uint256) {
        require(token == address(usdc), "only USDC !!");
        _updateInterest(msg.sender);
        return users[msg.sender].total_supply;
    }

    receive() external payable { }
}
