// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,    
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

interface IERC20 {
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
}

contract UniswapV2PairCreator {
    address constant UNISWAP_V2_FACTORY_ADDRESS = 0x7E0987E5b3a30e3f2828572Bb659A548460a3003;
    address constant UNISWAP_V2_ROUTER_ADDRESS = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;

    // Check if a pair exists
    function checkIfPairExists(address tokenA, address tokenB) public view returns (bool exists) {
        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(UNISWAP_V2_FACTORY_ADDRESS);
        address pair = uniswapFactory.getPair(tokenA, tokenB);
        return pair != address(0);
    }

    // Create a new pair for two tokens
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != address(0) && tokenB != address(0), "Invalid token address");
        require(tokenA != tokenB, "Tokens must be different");

        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(UNISWAP_V2_FACTORY_ADDRESS);
        pair = uniswapFactory.createPair(tokenA, tokenB);

        require(pair != address(0), "Pair creation failed");

        return pair;
    }

    // Add liquidity to the pair
    function addLiquidity(address tokenA, address tokenB) external {
        require(tokenA != address(0) && tokenB != address(0), "Invalid token address");

        uint amountA = 10 * (10 ** 18); // Assuming tokens have 18 decimals
        uint amountB = 10 * (10 ** 18);

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        IERC20(tokenA).approve(UNISWAP_V2_ROUTER_ADDRESS, amountA);
        IERC20(tokenB).approve(UNISWAP_V2_ROUTER_ADDRESS, amountB);

        IUniswapV2Router uniswapRouter = IUniswapV2Router(UNISWAP_V2_ROUTER_ADDRESS);
        uniswapRouter.addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            0, // amountAMin
            0, // amountBMin
            msg.sender, // to
            block.timestamp + 300 // deadline
        );
    }
}
// 0xee710f63b1f097a0736D821FcB4bcaeF18783229
// 0x9b49fa1DAB708D7429f0A315882CF85318b0dBD4