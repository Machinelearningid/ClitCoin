pragma solidity ^0.4.11;

/// @title Clit Token (CLIT) - Crowd funding code for CLIT Coin project
/// 


contract ClitCoinToken is MiniMeToken {


	function ClitCoinToken(
		//address _tokenFactory
	) MiniMeToken(
		0x0,
		0x0,            // no parent token
		0,              // no snapshot block number from parent
		"CLIT Token", 	// Token name
		0,              // Decimals
		"CLIT",         // Symbol
		true            // Enable transfers
	) {
		version = "CLIT 1.0";
	}


}

/*
 * Math operations with safety checks
 */
contract SafeMath {
  function mul(uint a, uint b) internal returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint a, uint b) internal returns (uint) {
    assert(b > 0);
    uint c = a / b;
    assert(a == b * c + a % b);
    return c;
  }

  function sub(uint a, uint b) internal returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function add(uint a, uint b) internal returns (uint) {
    uint c = a + b;
    assert(c >= a);
    return c;
  }
}


contract ClitCrowdFunder is Controlled, SafeMath {

	address public creator;
    address public fundRecipient;
	
	// State variables
    State public state = State.Fundraising; // initialize on create	
    uint public fundingGoal; 
	uint public currentBalance;
	uint public tokensIssued;
	uint public capTokenAmount;
	uint public startBlockNumber;
	uint public endBlockNumber;
	uint public eolBlockNumber;
	
	uint public firstExchangeRatePeriod;
	uint public secondExchangeRatePeriod;
	uint public thirdExchangeRatePeriod;
	uint public fourthExchangeRatePeriod;
	
	uint public firstTokenExchangeRate;
	uint public secondTokenExchangeRate;
	uint public thirdTokenExchangeRate;
	uint public fourthTokenExchangeRate;

	uint public finalTokenExchangeRate;
	
    ClitCoinToken public exchangeToken;
	
	/* This generates a public event on the blockchain that will notify clients */
	event GoalReached(address fundRecipient, uint amountRaised);
	event FundTransfer(address backer, uint amount, bool isContribution);	
	event FrozenFunds(address target, bool frozen);
	event LogFundingReceived(address addr, uint amount, uint currentTotal);

	/* data structure to hold information about campaign contributors */
	mapping(address => uint256) private balanceOf;
	mapping (address => bool) private frozenAccount;
	
	// Data structures
    enum State {
		Fundraising,
		ExpiredRefund,
		Successful,
		Closed
	}
	
	/*
     *  Modifiers
     */

	modifier inState(State _state) {
        if (state != _state) throw;
        _;
    }
	
	// Add one week to endBlockNumber
	modifier atEndOfLifecycle() {
        if(!((state == State.ExpiredRefund || state == State.Successful) && block.number > eolBlockNumber)) {
            throw;
        }
        _;
    }
	
	modifier accountNotFrozen() {
        if (frozenAccount[msg.sender] == true) throw;
        _;
    }
	
    modifier minInvestment() {
      // User has to send at least 0.01 Eth
      require(msg.value >= 10 ** 16);
      _;
    }
	
	modifier isStarted() {
		require(block.number >= startBlockNumber);
		_;
	}

	/*  at initialization, setup the owner */
	function ClitCrowdFunder(
		address _fundRecipient,
		uint _delayStartHours,
		ClitCoinToken _addressOfExchangeToken
	) {
		creator = msg.sender;
		
		fundRecipient = _fundRecipient;
		fundingGoal = 7000 * 1 ether;
		capTokenAmount = 140 * 10 ** 6;
		state = State.Fundraising;
		
		//deadline = now + _durationInMinutes * 1 minutes;
		currentBalance = 0;
		tokensIssued = 0;
		
		startBlockNumber = block.number + div(mul(3600, _delayStartHours), 14);
		endBlockNumber = startBlockNumber + div(mul(3600, 1080), 14); // 45 days 
		eolBlockNumber = endBlockNumber + div(mul(3600, 168), 14);  // one week - contract end of life

		firstExchangeRatePeriod = startBlockNumber + div(mul(3600, 24), 14);   // First 24 hour sale 
		secondExchangeRatePeriod = firstExchangeRatePeriod + div(mul(3600, 240), 14); // Next 10 days
		thirdExchangeRatePeriod = secondExchangeRatePeriod + div(mul(3600, 240), 14); // Next 10 days
		fourthExchangeRatePeriod = thirdExchangeRatePeriod + div(mul(3600, 240), 14); // Next 10 days
		
		uint _tokenExchangeRate = 1000;
		firstTokenExchangeRate = (_tokenExchangeRate + 1000);	
		secondTokenExchangeRate = (_tokenExchangeRate + 500);
		thirdTokenExchangeRate = (_tokenExchangeRate + 300);
		fourthTokenExchangeRate = (_tokenExchangeRate + 100);
		finalTokenExchangeRate = _tokenExchangeRate;
		
		exchangeToken = ClitCoinToken(_addressOfExchangeToken);
	}
	
	function freezeAccount(address target, bool freeze) onlyController {
        frozenAccount[target] = freeze;
        FrozenFunds(target, freeze);
    }	
	
	function getCurrentExchangeRate(uint amount) public constant returns(uint) {
		if (block.number <= firstExchangeRatePeriod) {
			return firstTokenExchangeRate * amount / 1 ether;
		} else if (block.number <= secondExchangeRatePeriod) {
			return secondTokenExchangeRate * amount / 1 ether;
		} else if (block.number <= thirdExchangeRatePeriod) {
			return thirdTokenExchangeRate * amount / 1 ether;
		} else if (block.number <= fourthExchangeRatePeriod) {
			return fourthTokenExchangeRate * amount / 1 ether;
		} else if (block.number <= endBlockNumber) {
			return finalTokenExchangeRate * amount / 1 ether;
		}
		
		return finalTokenExchangeRate * amount / 1 ether;
	}

	function investment() public inState(State.Fundraising) isStarted accountNotFrozen minInvestment payable returns(uint)  {
		
		uint amount = msg.value;
		if (amount == 0) throw;
		
		balanceOf[msg.sender] += amount;	
		currentBalance += amount;
						
		uint tokenAmount = getCurrentExchangeRate(amount);
		exchangeToken.generateTokens(msg.sender, tokenAmount);
		tokensIssued += tokenAmount;
		
		FundTransfer(msg.sender, amount, true); 
		LogFundingReceived(msg.sender, tokenAmount, tokensIssued);
		
		checkIfFundingCompleteOrExpired();
		
		return balanceOf[msg.sender];
	}

	
	function checkIfFundingCompleteOrExpired() {
		if ( block.number > endBlockNumber || tokensIssued >= capTokenAmount ) {
			if (currentBalance > fundingGoal) {
				state = State.Successful;
				payOut();
				
				GoalReached(fundRecipient, currentBalance);

			} else  {
				state = State.ExpiredRefund; // backers can now collect refunds by calling getRefund()
			}
		}
	}

	function payOut() public inState(State.Successful) {

		var amount = currentBalance;
		currentBalance = 0;
		state = State.Closed;

		fundRecipient.transfer(amount);
		
		// Update the token reserve amount so that 50% of tokens remain in reserve
		exchangeToken.generateTokens(fundRecipient, tokensIssued);				

		// Transfer ownership back to our creator
		exchangeToken.changeController(controller);
	}

	function getRefund() public inState(State.ExpiredRefund) {	
		uint amountToRefund = balanceOf[msg.sender];
		balanceOf[msg.sender] = 0;
		
		// throws error if fails
		msg.sender.transfer(amountToRefund);
		currentBalance -= amountToRefund;
		
		FundTransfer(msg.sender, amountToRefund, false);
	}
	
	function removeContract() public atEndOfLifecycle onlyController() {		
		if (state != State.Closed) {
			exchangeToken.changeController(controller);
		}
		selfdestruct(msg.sender);
	}
	
	/* The function without name is the default function that is called whenever anyone sends funds to a contract */
	function () inState(State.Fundraising) accountNotFrozen payable { 
		investment(); 
	}	

}
