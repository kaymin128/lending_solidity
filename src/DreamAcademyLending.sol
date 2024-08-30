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
        require(msg.value > 0, "value should be bigger than zero");
        deposit(token, 1 wei);
    }

    function deposit(address token, uint256 amount) public payable {
        if (token == address(0x0)) { // eth
            require(msg.value == amount, "incorrect ether amount");
            users[msg.sender].deposited_ether += amount;
            users[msg.sender].total_supply += amount * oracle.getPrice(address(0x0)) / 1e18;
            total_supply += amount * oracle.getPrice(address(0x0)) / 1e18;
        } 
        else { // USDC
            require(usdc.transferFrom(msg.sender, address(this), amount), "USDC transfer failed");
            users[msg.sender].deposited_usdc += amount;
            if (amount != 1){
                users[address(msg.sender)].total_supply += amount * oracle.getPrice(address(usdc)) / 1e18;
                total_supply += amount * oracle.getPrice(address(usdc)) / 1e18;
            }
        } 
    }

    function borrow(address token, uint256 amount) external {
        require(token == address(usdc), "only USDC can be borrowed");

        _updateInterest(msg.sender); 

        uint256 ether_collateral_value = users[msg.sender].deposited_ether * oracle.getPrice(address(0x0)) / 1e18;
        uint256 usdc_collateral_value = users[msg.sender].deposited_usdc * oracle.getPrice(address(usdc)) / 1e18;
        uint256 total_collateral_value = ether_collateral_value + usdc_collateral_value;

        uint256 max_borrow = total_collateral_value * 50 / 100;

        require(amount + users[msg.sender].borrowed_usdc <= max_borrow, "not enough collateral");
        require(total_supply >= amount, "not enough liquidity in the protocol");

        users[msg.sender].borrowed_usdc += amount;
        total_borrowed += amount;
        total_supply -= amount;

        require(usdc.transfer(msg.sender, amount), "USDC transfer failed");
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

    function withdraw(address token, uint256 amount) external {
        _updateInterest(msg.sender); 
        uint256 ether_collateral_value = users[msg.sender].deposited_ether * oracle.getPrice(address(0x0)) / 1e18;
        uint256 usdc_collateral_value = users[msg.sender].deposited_usdc * oracle.getPrice(address(usdc)) / 1e18;
        uint256 total_collateral_value = ether_collateral_value + usdc_collateral_value;

        uint256 max_borrow = total_collateral_value * 50 / 100;
        
        require(amount + users[msg.sender].borrowed_usdc <= max_borrow, "not enough collateral");
        
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

        uint256 ether_collateral_value = users[user].deposited_ether * oracle.getPrice(address(0x0)) / 1e18;
        uint256 usdc_collateral_value = users[user].deposited_usdc;
        uint256 total_collateral_value = ether_collateral_value + usdc_collateral_value;
        uint256 user_debt = users[user].borrowed_usdc;

        require(total_collateral_value * 75 / 100 < user_debt, "enough collateral !");

        uint256 max_liquidatable_debt = user_debt * 25 / 100;
        require(amount <= max_liquidatable_debt, "can't liquidate more than 25% of debt");

        users[user].borrowed_usdc -= amount;
        total_borrowed -= amount;

        uint256 reward_ether = (amount * 1e18) / oracle.getPrice(address(0x0));
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
        console.log("im interest_updating func");
        console.log("supplyInterest:", supply_interest);

        users[user].total_supply += supply_interest;
        users[user].last_interest_block = block.number; 
    }

    function getAccruedSupplyAmount(address token) external returns (uint256) {
        require(token == address(usdc), "only USDC !!");
        _updateInterest(msg.sender);
        console.log("users[msg.sender].total_supply:", users[msg.sender].total_supply / 1 ether);
        return users[msg.sender].total_supply;
    }

    receive() external payable { }
}
