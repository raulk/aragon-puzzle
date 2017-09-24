pragma solidity ^0.4.17;

import { AragonStructs } from "./Structs.sol";

// For the sake of simplicity lets asume USD is a ERC20 token
// Also lets asume we can 100% trust the exchange rate oracle
interface PayrollInterface  {
    
  /* OWNER ONLY */
  function addEmployee(address accountAddress, address[] allowedTokens, uint256 initialYearlyUSDSalary) public;
  function setEmployeeSalary(uint256 employeeId, uint256 yearlyUSDSalary) public;
  function removeEmployee(uint256 employeeId) public;

  function addFunds() payable public;
  function scapeHatch() public;
  // function addTokenFunds()? // Use approveAndCall or ERC223 tokenFallback

  function getEmployeeCount() public constant returns (uint256);
  
  // Since it said "return all important info too", I take the liberty to enhance the return tuple with Employee.
  function getEmployee(uint256 employeeId) public constant returns (address employee, AragonStructs.Employee emp);

  function calculatePayrollBurnrate() public constant returns (uint256); // Monthly usd amount spent in salaries
  function calculatePayrollRunway() public constant returns (uint256); // Days until the contract can run out of funds

  /* EMPLOYEE ONLY */
  function determineAllocation(address[] tokens, uint256[] distribution) public; // only callable once every 6 months
  function payday() public; // only callable once a month

  /* ORACLE ONLY */
  function setExchangeRate(address token, uint256 usdExchangeRate) public; // uses decimals from token
}