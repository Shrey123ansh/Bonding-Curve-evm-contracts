// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./Token.sol";
import "hardhat/console.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TokenFactory is  Ownable {

    struct memeToken {
        string name;
        string symbol;
        string description;
        string tokenImageUrl;
        uint fundingRaised;
        address tokenAddress;
        address creatorAddress;
    }

    address[] public memeTokenAddresses;

    address public pTokenAddress;

    constructor(address _pTokenAddress) Ownable(msg.sender) {
        require(_pTokenAddress != address(0), "Invalid PToken address");
        pTokenAddress = _pTokenAddress;
    }
    mapping(address => memeToken) public addressToMemeTokenMapping;

    address constant UNISWAP_V2_FACTORY_ADDRESS = 0xF62c03E08ada871A0bEb309762E260a7a6a880E6;
    address constant UNISWAP_V2_ROUTER_ADDRESS = 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3;

    uint constant DECIMALS = 10 ** 18;
    uint constant MAX_SUPPLY = 	1000000000 * DECIMALS;
    uint constant INIT_SUPPLY = 20 * MAX_SUPPLY / 100;

    uint constant MEMETOKEN_CREATION_PLATFORM_FEE = 1000;
    uint constant MEMECOIN_FUNDING_GOAL = 4000000 * DECIMALS;

    uint256 public constant INITIAL_PRICE = 5000000000000000;  // Initial price in wei (P0), 3.00 * 10^13
    uint256 public constant K = 8 * 10**15;  // Growth rate (k), scaled to avoid precision loss (0.01 * 10^18)

    // Function to calculate the cost in wei for purchasing `tokensToBuy` starting from `currentSupply`
    function calculateCost(uint256 currentSupply, uint256 tokensToBuy) public pure returns (uint256) {
        
            // Calculate the exponent parts scaled to avoid precision loss
        uint256 exponent1 = (K * (currentSupply + tokensToBuy)) / 10**18;
        uint256 exponent2 = (K * currentSupply) / 10**18;

        // Calculate e^(kx) using the exp function
        uint256 exp1 = exp(exponent1);
        uint256 exp2 = exp(exponent2);

        // Cost formula: (P0 / k) * (e^(k * (currentSupply + tokensToBuy)) - e^(k * currentSupply))
        // We use (P0 * 10^18) / k to keep the division safe from zero
        uint256 cost = (INITIAL_PRICE * 10**18 * (exp1 - exp2)) / K;  // Adjust for k scaling without dividing by zero
        return cost;
    }

    // Improved helper function to calculate e^x for larger x using a Taylor series approximation
    function exp(uint256 x) internal pure returns (uint256) {
        uint256 sum = 10**18;  // Start with 1 * 10^18 for precision
        uint256 term = 10**18;  // Initial term = 1 * 10^18
        uint256 xPower = x;  // Initial power of x
        
        for (uint256 i = 1; i <= 20; i++) {  // Increase iterations for better accuracy
            term = (term * xPower) / (i * 10**18);  // x^i / i!
            sum += term;

            // Prevent overflow and unnecessary calculations
            if (term < 1) break;
        }

        return sum;
    }

    function createMemeToken(string memory name, string memory symbol, string memory imageUrl, string memory description) public payable returns(address) {

        // Define the required amount of PToken
        uint requiredAmount = MEMETOKEN_CREATION_PLATFORM_FEE * DECIMALS; // Assuming PToken has 18 decimals

        // Check if the user has approved enough tokens for the contract
        IERC20 pToken = IERC20(pTokenAddress);
        require(pToken.allowance(msg.sender, address(this)) >= requiredAmount, "Insufficient allowance for PToken");

        // Transfer the required amount of PToken from the sender to the contract
        require(pToken.transferFrom(msg.sender, address(this), requiredAmount), "PToken transfer failed");

        Token ct = new Token(name, symbol, INIT_SUPPLY);
        address memeTokenAddress = address(ct);
        memeToken memory newlyCreatedToken = memeToken(name, symbol, description, imageUrl, 0, memeTokenAddress, msg.sender);
        memeTokenAddresses.push(memeTokenAddress);
        addressToMemeTokenMapping[memeTokenAddress] = newlyCreatedToken;
        return memeTokenAddress;
    }

    function getAllMemeTokens() public view returns(memeToken[] memory) {
        memeToken[] memory allTokens = new memeToken[](memeTokenAddresses.length);
        for (uint i = 0; i < memeTokenAddresses.length; i++) {
            allTokens[i] = addressToMemeTokenMapping[memeTokenAddresses[i]];
        }
        return allTokens;
    }

    function buyMemeToken(address memeTokenAddress, uint256 tokenQty) public returns (uint256) {
        // Check if memecoin is listed
        require(addressToMemeTokenMapping[memeTokenAddress].tokenAddress != address(0), "Token is not listed");

        memeToken storage listedToken = addressToMemeTokenMapping[memeTokenAddress];
        Token memeTokenCt = Token(memeTokenAddress);

        // Check to ensure funding goal is not met
        require(listedToken.fundingRaised <= MEMECOIN_FUNDING_GOAL, "Funding has already been raised");

        // Check to ensure there is enough supply to facilitate the purchase
        uint currentSupply = memeTokenCt.totalSupply();
        uint available_qty = MAX_SUPPLY - currentSupply;
        uint scaled_available_qty = available_qty / DECIMALS;
        uint tokenQty_scaled = tokenQty * DECIMALS;

        require(tokenQty <= scaled_available_qty, "Not enough available supply");

        // Calculate the cost for purchasing tokenQty tokens using the bonding curve formula
        uint currentSupplyScaled = (currentSupply - INIT_SUPPLY) / DECIMALS;
        uint requiredPToken = calculateCost(currentSupplyScaled, tokenQty);

        // Check if user has approved and has enough PToken balance
        IERC20 pToken = IERC20(pTokenAddress); // Ensure `pTokenAddress` is initialized elsewhere in the contract
        require(pToken.allowance(msg.sender, address(this)) >= requiredPToken, "Insufficient PToken allowance");
        require(pToken.balanceOf(msg.sender) >= requiredPToken, "Insufficient PToken balance");

        // Transfer PToken from the user to the contract
        require(pToken.transferFrom(msg.sender, address(this), requiredPToken), "PToken transfer failed");

        // Increment the funding raised
        listedToken.fundingRaised += requiredPToken;

        if (listedToken.fundingRaised >= MEMECOIN_FUNDING_GOAL) {
            // Create liquidity pool
            address pool = _createLiquidityPool(memeTokenAddress);

            // Provide liquidity
            uint pTokenAmount = 60 * listedToken.fundingRaised / 100;
            uint liquidity = _provideLiquidity(memeTokenAddress, INIT_SUPPLY, pTokenAmount);

            // Burn LP tokens
            _burnLpTokens(pool, liquidity);
        }

        // Mint the tokens to the buyer
        memeTokenCt.mint(tokenQty_scaled, msg.sender);

        return 1;
    }

    function _createLiquidityPool(address memeTokenAddress) internal returns(address) {
        IUniswapV2Factory factory = IUniswapV2Factory(UNISWAP_V2_FACTORY_ADDRESS);
        address pair = factory.createPair(memeTokenAddress, pTokenAddress);
        return pair;
    }

    function _provideLiquidity(address memeTokenAddress, uint tokenAmount, uint ethAmount) internal returns(uint){
        Token memeTokenCt = Token(memeTokenAddress);
        memeTokenCt.approve(UNISWAP_V2_ROUTER_ADDRESS, tokenAmount);
        IUniswapV2Router01 router = IUniswapV2Router01(UNISWAP_V2_ROUTER_ADDRESS);
        (,, uint liquidity) = router.addLiquidityETH{
            value: ethAmount
        }(memeTokenAddress, tokenAmount, tokenAmount, ethAmount, address(this), block.timestamp);
        return liquidity;
    }

    function _burnLpTokens(address pool, uint liquidity) internal returns(uint){
        IUniswapV2Pair uniswapv2pairct = IUniswapV2Pair(pool);
        uniswapv2pairct.transfer(address(0), liquidity);
        console.log("Uni v2 tokens burnt");
        return 1;
    }

  function withdrawPTOKEN() public onlyOwner {
    IERC20 pToken = IERC20(pTokenAddress); 
    uint256 balance = pToken.balanceOf(address(this));
    require(balance > 0, "No PTOKEN to withdraw");

    bool success = pToken.transfer(msg.sender, balance);
    require(success, "PTOKEN withdrawal failed");
}



}