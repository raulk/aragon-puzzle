pragma solidity ^0.4.17;

import { AragonStructs } from "./Structs.sol";
import "./PayrollInterface.sol";
import "./ERC667ReceiverInterface.sol";
import "./ERC20Interface.sol";


/* NOTES:
   ------
   Not using any external libraries, i.e. no date utils, no array utils, etc.
   Not worrying too much about optimisation.
   Using ERC667 tokenFallback.
   Assuming oracle will set USD FX rate = 1
*/
contract AragonPayroll is PayrollInterface, ERC667ReceiverInterface {
    
    // ----- CONSTANTS -----
    // For simplicity, I'm assuming 30-day months.
    uint MIN_TIME_BETWEEN_ALLOCATIONS = 180 days;
    uint MIN_TIME_BETWEEN_PAYOUTS = 30 days;
    
    // ----- TOKENS -----
    mapping (address => bool) private allowedTokens;
    address[] private tokenAddrs;
    mapping (address => uint256) private balances;

    // ----- KEY STAKEHOLDERS -----
    address internal owner;
    address internal oracle;
    
    // ----- EMPLOYEES -----
    // Employees are added by address, but are subsequently referred to by ID.
    // This ID will be sequential and it refers to an array index.
    // Employee structs are stored in a map keyed by employee's address.
    // An array serves a lookup table between employee ID and address.
    mapping (address => AragonStructs.Employee) private employees;
    address[] internal employeeIdx;
    uint256 internal count = 0;
    
    // ----- EXCHANGE RATES -----
    mapping (address => uint256) private rates;
    
    
    modifier employeeOnly {
        require(employees[msg.sender].exists);
        _;
    }
    
    modifier ownerOnly {
        require(owner == msg.sender);
        _;
    }
    
    modifier oracleOnly {
        require(oracle == msg.sender);
        _;
    }
    
    modifier minimumTimeElapsed(uint _since, uint _elapsed) {
        require(now - _since >= _elapsed);
        _;
    }
    
    modifier employeeExists(uint256 _employeeId) {
        require(employeeIdx[_employeeId] != address(0));
        _;
    }
    
    modifier allRatesDefined {
        for (uint i = 0; i < tokenAddrs.length; i++) {
            require(tokenAddrs[i] != 0);
        }
        _;
    }
    
    // Ctor.
    function AragonSalaries(address _owner, address _oracle) public {
        owner = _owner;
        oracle = _oracle;
        
        // Add ourselves to the token superset, as holders of ETH.
        allowedTokens[this] = true;
        tokenAddrs.push(this);
    }
    
    function addFunds() payable public {
        require(msg.value > 0);
        balances[this] += msg.value;
    }
    
    function scapeHatch() public ownerOnly {
        owner.transfer(this.balance);
        
        // TODO: transfer all token holdings to owner.
        
        selfdestruct(this);
    }
    
    function tokenFallback(address _from, uint256 _amount, bytes) public returns (bool success) {
        // Do not accept the tokens if we don't recognise the sending address,
        // or if value is zero. We return false instead of using require, to 
        // preserve the interface.
        if (!allowedTokens[_from] || _amount <= 0) return false;
        
        balances[_from] += _amount;
        return true;
    }
    
    // Add an employee.
    function addEmployee(
        address _accountAddress, 
        address[] _allowedTokens, 
        uint256 _initialYearlyUSDSalary) 
        public ownerOnly 
    {
        // The employee must not exist yet, otherwise we'd override him/her.
        require(!employees[_accountAddress].exists);
        
        // Add all tokens to global superset.
        for (uint i = 0; i < _allowedTokens.length; i++) {
            var t = _allowedTokens[i];
            allowedTokens[t] = true;
            tokenAddrs.push(t);
        }
        
        // Add the employee's address to the ID index.
        employeeIdx.push(_accountAddress);
        
        // Create the employee and add him/her.
        AragonStructs.Employee memory employee = AragonStructs.Employee({
            allowedTokens: _allowedTokens, 
            tokens: new address[](0),
            exists: true, 
            yearlySalaryUsd: _initialYearlyUSDSalary, 
            lastPayoutTimestamp: now,
            lastAllocationTimestamp: 0,
            distribution: new uint256[](0)
        });
        
        employees[_accountAddress] = employee;
        
        count++;
        
        // Emit the event.
        EmployeeAdded(_accountAddress, employeeIdx.length - 1);
        
    }
    
    // Change the employee's salary.
    function setEmployeeSalary(uint256 _employeeId, uint256 _yearlyUSDSalary) public 
        ownerOnly 
        employeeExists(_employeeId)
    {
        var (, employee) = getEmployee(_employeeId);
        employee.yearlySalaryUsd = _yearlyUSDSalary;
    }
    
    // Delete an employee.
    function removeEmployee(uint256 _employeeId) public 
        ownerOnly 
        employeeExists(_employeeId)
    {
        var (addr, ) = getEmployee(_employeeId);
        delete employeeIdx[_employeeId];
        delete employees[addr];
        count--;
        
        // TODO: trigger a final payout.
    }
    
    // Return an employee address and struct.
    function getEmployee(uint256 _employeeId) public constant 
        returns (address, AragonStructs.Employee)
    {
        address addr = employeeIdx[_employeeId];
        AragonStructs.Employee storage employee = employees[addr];
        return (addr, employee);
    }
    
    // Return number of employees.
    function getEmployeeCount() public constant returns (uint256) {
        return count;
    }
    
    // Allows employees to change their token allocations every 6 months.
    // Assume sum of all distribution values == 100 (i.e. representing percentages).
    function determineAllocation(address[] _tokens, uint256[] _distribution) public 
        employeeOnly
        minimumTimeElapsed(employees[msg.sender].lastAllocationTimestamp, MIN_TIME_BETWEEN_ALLOCATIONS)
    {
        // Soundness check on distribution.
        require(_tokens.length == _distribution.length);
        checkSumEquals(_distribution, 100);
        
        AragonStructs.Employee storage employee = employees[msg.sender];
        var allowedTokens = employee.allowedTokens;
        
        // Check that all tokens are allowed for the employee.
        for (uint i = 0; i < _tokens.length; i++) {
            bool found = false;
            for (uint j = 0; j < allowedTokens.length; j++) {
                if (allowedTokens[j] == _tokens[i]) {
                    found = true;
                    break;
                }
            }
            require(found);
        }
        
        employee.tokens = _tokens;
        employee.distribution = _distribution;
        employee.lastAllocationTimestamp = now;
    }
    
    function payday() public 
        employeeOnly 
        minimumTimeElapsed(employees[msg.sender].lastPayoutTimestamp, MIN_TIME_BETWEEN_PAYOUTS)
        allRatesDefined
    {
        AragonStructs.Employee storage employee = employees[msg.sender];
        uint256 monthlySalaryUsd = employee.yearlySalaryUsd / 12;
        
        for (uint i = 0; i < employee.tokens.length; i++) {
            var token = employee.tokens[i];
            var distrib = employee.distribution[i];
            var payableUsd = monthlySalaryUsd * distrib / 100;
            var rate = rates[token];
            var tokenAmount = payableUsd / rate;
            
            require(balances[token] >= tokenAmount);
            
            if (token == address(this)) {
                msg.sender.transfer(tokenAmount);
            } else {
                ERC20(token).transfer(msg.sender, tokenAmount);
            }
        }
        
        employee.lastPayoutTimestamp = now;
    }
    
    // Set exchange rates, only callable by oracle.
    function setExchangeRate(address _token, uint256 usdExchangeRate) public oracleOnly {
        require(allowedTokens[_token]);
        rates[_token] = usdExchangeRate;
    }
    
    // Calculate monthly USD total salaries paid.
    function calculatePayrollBurnrate() public constant 
        allRatesDefined 
        returns (uint256)
    {
        // Quick return if no employees, or all employees deleted.
        if (count == 0) return 0;
        
        uint256 burnRate = 0;
        for (uint i = 0; i < employeeIdx.length; i++) {
            address addr = employeeIdx[i];
            // If this position is empty, skip (employee deleted).
            if (addr == address(0)) continue;
            burnRate += calculateNormalizedPay(employees[addr]);
        }
        return burnRate;
    }
    
    function calculatePayrollRunway() public constant returns (uint256) {
        // TODO;
    }
    
    function calculateNormalizedPay(AragonStructs.Employee _employee) constant internal returns (uint) {
        uint pay = 0;
        for (uint i = 0; i < _employee.tokens.length; i++) {
            pay += rates[_employee.tokens[i]] * _employee.distribution[i];
        }
        return pay;
    }
    
    function checkSumEquals(uint[] _values, uint ref) pure internal {
        uint accumulator = 0;
        for (uint i = 0; i < _values.length; i++) {
            accumulator += _values[i];
        }
        require(accumulator == ref);
    }

    event EmployeeAdded(address indexed _address, uint256 indexed employeeId);
    
}