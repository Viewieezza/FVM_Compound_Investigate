pragma solidity ^0.6.0;


interface IERC20 {

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    

    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);


    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface ComptrollerInterface{
    function liquidityOf(address account) external view returns (uint256);
    function borrowOf(address account) external view returns (uint256);
    function AllowAmountBorrow(address account)external view returns(uint256);
    function AllowRedeem(address account, uint256 valueAmountRedeem) external view returns(bool);
    

}

interface oraclePricefeedInterface{
    
    function getPrice() external view returns(uint256);
    
}


contract CToken is IERC20, ComptrollerInterface, oraclePricefeedInterface{
    
    address public admin_;
    address underlying_;
    uint256 initialExchangeRateMantissa_ ;
    uint256 totalSupply_;
    
    
    string public name_;
    string public symbol_;
    uint8 public decimals_;
    address public CompAddr_; 
    address public myComptrollerAddress_;
    IERC20 tokenContract;
    IERC20 CompContract;
    ComptrollerInterface ComptrollerAddress_;
    address OraclePriceFeed_;
    constructor(string memory name, string memory symbol, uint8 decimals, address underlying, address ComptrollerAddress, address CompAddr, uint256 initialExchangeRateMantissa) public{
        
        name_ = name;
        symbol_ = symbol;
        decimals_ = decimals;
        
        CompAddr_ = CompAddr;
        underlying_ = underlying;
        initialExchangeRateMantissa_ = initialExchangeRateMantissa;
        tokenContract = IERC20(underlying_);
        CompContract = IERC20(CompAddr); //maybe not used
        admin_ = msg.sender;
        ComptrollerAddress_ = ComptrollerInterface(ComptrollerAddress);
        myComptrollerAddress_ = ComptrollerAddress;
        
    }
    
    using SafeMath for uint256;
    
    function setCompAddr(address newCompAddr) external returns(bool){
        require(msg.sender == admin_);
        CompAddr_ = newCompAddr;
        CompContract = IERC20(CompAddr_);
        return true;
    }
    
    function setNewComptrollerAddress(address newComptrollerAddr) external returns(bool){
        require(msg.sender == admin_);
        ComptrollerAddress_ = ComptrollerInterface(newComptrollerAddr);
        return true;
    }
    
    function checkApprove(address owner,uint256 tokenAmount) internal view returns (bool){
        if (tokenContract.allowance(owner,address(this))<tokenAmount){
            return false;
        }
        else{
            return true;
        }
      
    }
    function checkApproveCToken(address owner,uint256 tokenAmount) internal view returns (bool){
        if (allowance(owner,address(this))<tokenAmount){
            return false;
        }
        else{
            return true;
        }
      
    }
    
    function checkUnderlyingToken(uint256 tokenAmount) internal view returns(bool){
        if (tokenContract.balanceOf(address(this))<tokenAmount){
            return false;
        }
        else{
            return true;
        }
    }
    
    function checkAmountCToken(address owner,uint256 tokenAmount) internal view returns(bool){
        if (balanceOf(owner)<tokenAmount){
            return false;
        }
        else{
            return true;
        }
    }
    
    function getExchangeRate() internal view returns(uint256){
        return initialExchangeRateMantissa_;
    }
    
    //mint, reddem, claim CompAddr_
    function mint(uint256 mintAmount) external returns (bool){
      
      require(checkApprove(msg.sender,mintAmount));  
      
      uint256 cTokenAmount = mintAmount.mul(getExchangeRate());
      totalSupply_ = totalSupply_.add(cTokenAmount);
      tokenContract.transferFrom(msg.sender,address(this),mintAmount);
      
      balances[msg.sender] = balances[msg.sender].add(cTokenAmount);
      calculateComp_mint(balances[msg.sender]); //We will add interest later
      
      addLiquiduty(msg.sender, mintAmount);
      
      approve(address(this),1e18);
      return true;
      
       }
       
    function redeem(uint256 redeemTokens) external returns (bool){
        
        require(checkApproveCToken(msg.sender,redeemTokens));
        uint256 underlyingToken = redeemTokens.div(getExchangeRate());
        require(checkUnderlyingToken(underlyingToken));
        require(checkAmountCToken(msg.sender,redeemTokens));
        //require(AllowRedeem(msg.sender,underlyingToken.mul(getPrice()))); 
        
      
        tokenContract.transfer(msg.sender,underlyingToken);
        
        balances[msg.sender] = balances[msg.sender].sub(redeemTokens);
        totalSupply_ = totalSupply_.sub(redeemTokens);
        
        subLiquidity(msg.sender, underlyingToken);
        
        calculateComp_redeem(balances[msg.sender]); //We will add interest later
        
        return true;
    }
    
    function redeemUnderlying(uint256 redeemTokens) external returns (bool){
        
        require(checkApprove(msg.sender,redeemTokens)); 
        uint256 cTokenAmount = redeemTokens.mul(getExchangeRate());
        require(checkUnderlyingToken(redeemTokens));
        require(checkAmountCToken(msg.sender,cTokenAmount));
        //require(AllowRedeem(msg.sender,redeemTokens.mul(getPrice())));
        
        tokenContract.transfer(msg.sender,redeemTokens);
        balances[msg.sender] = balances[msg.sender].sub(cTokenAmount);
        totalSupply_ = totalSupply_.sub(cTokenAmount);
        
        subLiquidity(msg.sender, redeemTokens);
        
        calculateComp_redeem(balances[msg.sender]); //We will add interest later
        
        return true;
       
    }
    
    
    
    function calculateComp_mint(uint256 mintAmount) internal returns(bool){
        uint256 CompAmount = calculateComp(startBlock[msg.sender],mintAmount);
        Compbalances[msg.sender] = Compbalances[msg.sender].add(CompAmount);
        uint currentblock = block.timestamp;
        startBlock[msg.sender] = currentblock;
        
        return true;
        
        
    }
    
    function calculateComp_redeem(uint256 redeemAmount) internal returns(bool){
        ClaimComp(calculateComp(startBlock[msg.sender],redeemAmount));
        Compbalances[msg.sender] = Compbalances[msg.sender].sub(calculateComp(startBlock[msg.sender],redeemAmount));
        startBlock[msg.sender] = block.timestamp;
        
        return true;
        
    }
    
    function ClaimComp(uint256 amount) public {
        CompContract.transferFrom(myComptrollerAddress_,msg.sender,amount);
    }

    function addLiquiduty(address account, uint256 amount) internal returns(bool){
        liquidity[account] = liquidity[account].add(amount.mul(getPrice()));
        return true;
    }
    
    function subLiquidity(address account, uint256 amount) internal returns(bool){
        if (!(liquidity[account]>=amount.mul(getPrice()))){
            return false;
        }
        else{
            liquidity[account] = liquidity[account].sub(amount.mul(getPrice()));
            return true;
        }
    }
    
    
    //borrow and repayBorrow function
    
    function liquidityOf(address account) public override view returns(uint256){
        return liquidity[account].mul(getPrice());
    }
    
    function borrowOf(address account) public override view returns(uint256){
        return borrowBalance[account].mul(getPrice());
    }
    
    function AllowAmountBorrow(address account) public override view returns(uint256){
        return ComptrollerAddress_.AllowAmountBorrow(account);
        
    }
    
    function AllowRedeem(address account, uint256 valueAmountRedeem) public override view returns(bool){
        return ComptrollerAddress_.AllowRedeem(account, valueAmountRedeem);
    }
    

    
    function borrow(uint256 borrowAmount) external returns (bool){
        //require(AllowedBorrow(msg.sender,borrowAmount)); 
        
        tokenContract.transfer(msg.sender,borrowAmount);
        borrowBalance[msg.sender] = borrowBalance[msg.sender].add(borrowAmount);
        return true;
    }
    //not finished yet
    function repayBorrow(uint256 repayAmount) external returns (bool){
        //require(AllowRepayBorrow(msg.sender,repayAmount));
        tokenContract.transferFrom(msg.sender,address(this),repayAmount);
        borrowBalance[msg.sender] = borrowBalance[msg.sender].sub(repayAmount);
        return true;
    }
    
    //not finished yet
    function AllowedBorrow(address account,uint256 borrowAmount) internal view returns (bool){
        
        
        if (AllowAmountBorrow(account) < (borrowAmount.mul(getPrice()))*80/100){
          
        
            //return false; 
            return true;
            
        }
        else {
           // return true; 
           return true;
            
        }
    
    }
    
    function AllowRepayBorrow(address account, uint256 repayAmount) internal view returns(bool){
        if (repayAmount > borrowBalance[account]){
            return false;
        }
        else{
            return true;
        }
    }

    
    
    function debugblock(address sender) external view returns(uint256){
        return startBlock[sender];
    }
    
    function debugComp(address sender) external view returns(uint256){
        return Compbalances[sender];
    }
    
    // check & set OraclePriceFeed
    function setOraclePrice(address OracleAddress) external returns(address){
        require(msg.sender == admin_);
        OraclePriceFeed_ = OracleAddress;
    }
    
    function checkOraclePriceFeed() internal view returns(bool){
        if (OraclePriceFeed_ == address(0)){
            return false;
        }
        else{
            return true;
        }
    }
    
    function getPrice() public override view returns(uint256){
        
        
        if (!checkOraclePriceFeed()){
            return 1;
        }
        else{
            oraclePricefeedInterface oraclePriceContract = oraclePricefeedInterface(OraclePriceFeed_);
            return oraclePriceContract.getPrice();
        }
    }
    
    function admin() external view returns (address){
        return admin_;
    }
    
    
    
    function calculateComp(uint initialblock,uint256 tokenAmount) internal view returns(uint256){
        
        uint256 currentblock = block.timestamp;
        uint256 lengthPeriod = currentblock.sub(initialblock);
        uint256 rate = (tokenAmount.mul(getPrice())).mul(4*60*24/0.2/50);
        uint256 CompAmount = lengthPeriod.mul(rate);
        
        return CompAmount;
        
    }
    
   
    
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
    event Transfer(address indexed from, address indexed to, uint tokens);


    mapping(address => uint256) balances;
    mapping(address => mapping (address => uint256)) allowed;
    mapping(address => uint256) Compbalances;
    mapping(address => uint) startBlock;
    mapping(address => uint256) liquidity;
    mapping(address => uint256) borrowBalance;
   
    
    

    
    
    
    function totalSupply() public override view returns (uint256) {
    return totalSupply_;
    }

    function balanceOf(address tokenOwner) public override view returns (uint256) {
        return balances[tokenOwner];
    }

    function transfer(address receiver, uint256 numTokens) public override returns (bool) {
        require(numTokens <= balances[msg.sender]);
        balances[msg.sender] = balances[msg.sender].sub(numTokens);
        balances[receiver] = balances[receiver].add(numTokens);
        emit Transfer(msg.sender, receiver, numTokens);
        return true;
    }

    function approve(address delegate, uint256 numTokens) public override returns (bool) {
        allowed[msg.sender][delegate] = numTokens;
        emit Approval(msg.sender, delegate, numTokens);
        return true;
    }

    function allowance(address owner, address delegate) public override view returns (uint) {
        return allowed[owner][delegate];
    }

    function transferFrom(address owner, address buyer, uint256 numTokens) public override returns (bool) {
        require(numTokens <= balances[owner]);
        require(numTokens <= allowed[owner][msg.sender]);

        balances[owner] = balances[owner].sub(numTokens);
        allowed[owner][msg.sender] = allowed[owner][msg.sender].sub(numTokens);
        balances[buyer] = balances[buyer].add(numTokens);
        emit Transfer(owner, buyer, numTokens);
        return true;
    }
    
}



library SafeMath {
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
      assert(b <= a);
      return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
      uint256 c = a + b;
      assert(c >= a);
      return c;
    }
    
    function mul(uint256 a, uint256 b) internal pure returns (uint256){
        uint256 c = a * b;
        assert(c >= a);
        return c;
    }
    
    function div(uint256 a, uint256 b) internal pure returns (uint256){
        assert(b>0);
        return a / b;
    }
}