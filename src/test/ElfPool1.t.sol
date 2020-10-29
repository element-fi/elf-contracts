pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";
import "../interfaces/WETH.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "./AYVault.sol";
import "./ALender.sol";
import "./ASPV.sol";
import "./AToken.sol";
import "./APriceOracle.sol";
import "./ElfDeploy.sol";

import "../assets/YdaiAsset.sol";
import "../assets/YtusdAsset.sol";
import "../assets/YusdcAsset.sol";
import "../assets/YusdtAsset.sol";
import "../pools/low/Elf.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;
}

contract User {
    // max uint approve for spending
    function approve(address _token, address _guy) public {
        IERC20(_token).approve(_guy, uint256(-1));
    }

    // depositing WETH and minting
    function call_deposit(address payable _obj, uint256 _amount) public {
        Elf(_obj).deposit(_amount);
    }

    // deposit ETH, converting to WETH, and minting
    function call_depositETH(address payable _obj, uint256 _amount)
        public
        payable
    {
        Elf(_obj).depositETH{value: _amount}();
    }

    // withdraw specific shares to WETH
    function call_withdraw(address payable _obj, uint256 _amount) public {
        Elf(_obj).withdraw(_amount);
    }

    // withdraw specific shares to ETH
    function call_withdrawETH(address payable _obj, uint256 _amount) public {
        Elf(_obj).withdrawETH(_amount);
    }

    // to be able to receive funds
    receive() external payable {}
}

contract ElfContractsTest is DSTest {
    Hevm hevm;
    WETH weth;

    Elf elf;
    ElfAllocator allocator;

    ALender lender1;

    APriceOracle priceOracle1;
    APriceOracle priceOracle2;
    APriceOracle priceOracle3;
    APriceOracle priceOracle4;

    User user1;
    User user2;
    User user3;

    AToken dai;
    AToken tusd;
    AToken usdc;
    AToken usdt;

    ASPV spv1;
    ASPV spv2;
    ASPV spv3;
    ASPV spv4;

    AYVault ydai;
    AYVault ytusd;
    AYVault yusdc;
    AYVault yusdt;

    YdaiAsset ydaiAsset;
    YtusdAsset ytusdAsset;
    YusdcAsset yusdcAsset;
    YusdtAsset yusdtAsset;

    // for testing a basic 4x25% asset percent split
    address[] fromTokens = new address[](4);
    address[] toTokens = new address[](4);
    uint256[] percents = new uint256[](4);
    address[] assets = new address[](4);
    uint256[] conversionType = new uint256[](4);

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        ElfDeploy _elfDeploy = new ElfDeploy();
        _elfDeploy.init();

        weth = _elfDeploy.weth();
        elf = _elfDeploy.elf();
        allocator = _elfDeploy.allocator();

        _elfDeploy.config();

        priceOracle1 = _elfDeploy.priceOracle1();
        priceOracle2 = _elfDeploy.priceOracle2();
        priceOracle3 = _elfDeploy.priceOracle3();
        priceOracle4 = _elfDeploy.priceOracle4();

        // stablecoins
        dai = _elfDeploy.dai();
        tusd = _elfDeploy.tusd();
        usdc = _elfDeploy.usdc();
        usdt = _elfDeploy.usdt();

        // lending contracts
        spv1 = _elfDeploy.spv1();
        spv2 = _elfDeploy.spv2();
        spv3 = _elfDeploy.spv3();
        spv4 = _elfDeploy.spv4();

        // mint some stablecoins to spvs
        dai.mint(address(spv1), 10000000 ether);
        tusd.mint(address(spv2), 10000000 ether);
        usdc.mint(address(spv3), 10000000 ether);
        usdt.mint(address(spv4), 10000000 ether);

        // yvaults
        ydai = _elfDeploy.ydai();
        ytusd = _elfDeploy.ytusd();
        yusdc = _elfDeploy.yusdc();
        yusdt = _elfDeploy.yusdt();

        // element asset proxies
        ydaiAsset = _elfDeploy.ydaiAsset();
        ytusdAsset = _elfDeploy.ytusdAsset();
        yusdcAsset = _elfDeploy.yusdcAsset();
        yusdtAsset = _elfDeploy.yusdtAsset();

        // create 3 users and provide funds
        user1 = new User();
        user2 = new User();
        user3 = new User();
        address(user1).transfer(1000 ether);
        address(user2).transfer(1000 ether);
        address(user3).transfer(1000 ether);
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(user1), uint256(3))), // Mint user 1 1000 WETH
            bytes32(uint256(1000 ether))
        );
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(user2), uint256(3))), // Mint user 2 1000 WETH
            bytes32(uint256(1000 ether))
        );
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(user3), uint256(3))), // Mint user 3 1000 WETH
            bytes32(uint256(1000 ether))
        );
    }

    function test_correctUserBalances() public {
        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);
    }

    function test_depositingETH() public {
        // initial balance
        assertEq(address(user1).balance, 1000 ether);

        // deposit eth
        user1.call_depositETH(address(elf), 1 ether);
        assertEq(address(user1).balance, 999 ether);

        // verify that weth made it all the way to the lender
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(allocator)), 0 ether);

        assertEq(weth.balanceOf(address(spv1)), 250 finney);
        assertEq(weth.balanceOf(address(spv2)), 250 finney);
        assertEq(weth.balanceOf(address(spv3)), 250 finney);
        assertEq(weth.balanceOf(address(spv4)), 250 finney);

        assertEq(weth.balanceOf(address(spv1)), 250 finney);
        assertEq(ydaiAsset.vault().balanceOf(address(allocator)), 250 finney);

        assertEq(weth.balanceOf(address(spv2)), 250 finney);
        assertEq(ytusdAsset.vault().balanceOf(address(allocator)), 250 finney);

        assertEq(weth.balanceOf(address(spv3)), 250 finney);
        assertEq(yusdcAsset.vault().balanceOf(address(allocator)), 250 finney);

        assertEq(weth.balanceOf(address(spv4)), 250 finney);
        assertEq(yusdtAsset.vault().balanceOf(address(allocator)), 250 finney);

        // verify that the proper amount of elf was minted
        assertEq(elf.totalSupply(), 1 ether);

        // verify that the balance calculation matches the deposited eth
        // under current conditions, the below line will always calculate 0
        assertEq(elf.balance(), 1 ether);
        assertEq(weth.balanceOf(elf.allocator()), 0 ether);

        // assert 250 finney at each spv
        assertEq(weth.balanceOf(address(spv1)), 250 finney);
        assertEq(weth.balanceOf(address(spv2)), 250 finney);
        assertEq(weth.balanceOf(address(spv3)), 250 finney);
        assertEq(weth.balanceOf(address(spv4)), 250 finney);
    }

    function test_depositingWETH() public {
        // initial balance
        assertEq(weth.balanceOf(address(user1)), 1000 ether);

        // deposit eth
        user1.approve(address(weth), address(elf));
        user1.call_deposit(address(elf), 1 ether);
        assertEq(weth.balanceOf(address(user1)), 999 ether);

        // verify that weth made it all the way to the lender
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(allocator)), 0 ether);

        assertEq(weth.balanceOf(address(spv1)), 250 finney);
        assertEq(weth.balanceOf(address(spv2)), 250 finney);
        assertEq(weth.balanceOf(address(spv3)), 250 finney);
        assertEq(weth.balanceOf(address(spv4)), 250 finney);

        assertEq(weth.balanceOf(address(spv1)), 250 finney);
        assertEq(ydaiAsset.vault().balanceOf(address(allocator)), 250 finney);

        assertEq(weth.balanceOf(address(spv2)), 250 finney);
        assertEq(ytusdAsset.vault().balanceOf(address(allocator)), 250 finney);

        assertEq(weth.balanceOf(address(spv3)), 250 finney);
        assertEq(yusdcAsset.vault().balanceOf(address(allocator)), 250 finney);

        assertEq(weth.balanceOf(address(spv4)), 250 finney);
        assertEq(yusdtAsset.vault().balanceOf(address(allocator)), 250 finney);

        // verify that the proper amount of elf was minted
        assertEq(elf.totalSupply(), 1 ether);

        // verify that the balance calculation matches the deposited eth
        // under current conditions, the below line will always calculate 0
        assertEq(elf.balance(), 1 ether);
        assertEq(weth.balanceOf(elf.allocator()), 0 ether);

        // assert 250 finney at each spv
        assertEq(weth.balanceOf(address(spv1)), 250 finney);
        assertEq(weth.balanceOf(address(spv2)), 250 finney);
        assertEq(weth.balanceOf(address(spv3)), 250 finney);
        assertEq(weth.balanceOf(address(spv4)), 250 finney);
    }

    function test_multipleETHDeposits() public {
        // verify starting balance
        assertEq(address(user1).balance, 1000 ether);
        assertEq(address(user2).balance, 1000 ether);
        assertEq(address(user3).balance, 1000 ether);

        // Deposit 1
        user1.call_depositETH(address(elf), 1 ether);
        assertEq(address(user1).balance, 999 ether);

        assertEq(elf.totalSupply(), 1 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(allocator)), 0 ether);

        // ensure WETH is pushed to SPVs
        assertEq(weth.balanceOf(address(spv1)), 250 finney);
        assertEq(weth.balanceOf(address(spv2)), 250 finney);
        assertEq(weth.balanceOf(address(spv3)), 250 finney);
        assertEq(weth.balanceOf(address(spv4)), 250 finney);

        // ensure assets hold borrowed assets
        assertEq(ydaiAsset.vault().balanceOf(address(allocator)), 250 finney);
        assertEq(ytusdAsset.vault().balanceOf(address(allocator)), 250 finney);
        assertEq(yusdcAsset.vault().balanceOf(address(allocator)), 250 finney);
        assertEq(yusdtAsset.vault().balanceOf(address(allocator)), 250 finney);

        // this will never be anyone other than 0
        assertEq(elf.balance(), 1 ether);
        assertEq(elf.balanceOf(address(user1)), 1 ether);

        // Deposit 2
        user2.call_depositETH(address(elf), 1 ether);
        assertEq(address(user1).balance, 999 ether);

        assertEq(elf.totalSupply(), 2 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(allocator)), 0 ether);

        // ensure WETH is pushed to SPVs
        assertEq(weth.balanceOf(address(spv1)), 500 finney);
        assertEq(weth.balanceOf(address(spv2)), 500 finney);
        assertEq(weth.balanceOf(address(spv3)), 500 finney);
        assertEq(weth.balanceOf(address(spv4)), 500 finney);

        // ensure assets hold borrowed assets
        assertEq(ydaiAsset.vault().balanceOf(address(allocator)), 500 finney);
        assertEq(ytusdAsset.vault().balanceOf(address(allocator)), 500 finney);
        assertEq(yusdcAsset.vault().balanceOf(address(allocator)), 500 finney);
        assertEq(yusdtAsset.vault().balanceOf(address(allocator)), 500 finney);

        // this will never be anyone other than 0
        assertEq(elf.balance(), 2 ether);

        // Deposit 3
        user2.call_depositETH(address(elf), 1 ether);
        assertEq(address(user1).balance, 999 ether);

        assertEq(elf.totalSupply(), 3 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(allocator)), 0 ether);

        // ensure WETH is pushed to SPVs
        assertEq(weth.balanceOf(address(spv1)), 750 finney);
        assertEq(weth.balanceOf(address(spv2)), 750 finney);
        assertEq(weth.balanceOf(address(spv3)), 750 finney);
        assertEq(weth.balanceOf(address(spv4)), 750 finney);

        // ensure assets hold borrowed assets
        assertEq(ydaiAsset.vault().balanceOf(address(allocator)), 750 finney);
        assertEq(ytusdAsset.vault().balanceOf(address(allocator)), 750 finney);
        assertEq(yusdcAsset.vault().balanceOf(address(allocator)), 750 finney);
        assertEq(yusdtAsset.vault().balanceOf(address(allocator)), 750 finney);

        assertEq(elf.balance(), 3 ether);
    }

    function test_multipleWETHDeposits() public {
        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);

        // Deposit 1
        user1.approve(address(weth), address(elf));
        user1.call_deposit(address(elf), 1 ether);
        assertEq(weth.balanceOf(address(user1)), 999 ether);

        assertEq(elf.totalSupply(), 1 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(allocator)), 0 ether);

        // ensure WETH is pushed to SPVs
        assertEq(weth.balanceOf(address(spv1)), 250 finney);
        assertEq(weth.balanceOf(address(spv2)), 250 finney);
        assertEq(weth.balanceOf(address(spv3)), 250 finney);
        assertEq(weth.balanceOf(address(spv4)), 250 finney);

        // ensure assets hold borrowed assets
        assertEq(ydaiAsset.vault().balanceOf(address(allocator)), 250 finney);
        assertEq(ytusdAsset.vault().balanceOf(address(allocator)), 250 finney);
        assertEq(yusdcAsset.vault().balanceOf(address(allocator)), 250 finney);
        assertEq(yusdtAsset.vault().balanceOf(address(allocator)), 250 finney);

        assertEq(elf.balance(), 1 ether);
        assertEq(elf.balanceOf(address(user1)), 1 ether);

        // Deposit 2
        user2.approve(address(weth), address(elf));
        user2.call_deposit(address(elf), 1 ether);
        assertEq(weth.balanceOf(address(user2)), 999 ether);

        assertEq(elf.totalSupply(), 2 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(allocator)), 0 ether);

        // ensure WETH is pushed to SPVs
        assertEq(weth.balanceOf(address(spv1)), 500 finney);
        assertEq(weth.balanceOf(address(spv2)), 500 finney);
        assertEq(weth.balanceOf(address(spv3)), 500 finney);
        assertEq(weth.balanceOf(address(spv4)), 500 finney);

        // ensure assets hold borrowed assets
        assertEq(ydaiAsset.vault().balanceOf(address(allocator)), 500 finney);
        assertEq(ytusdAsset.vault().balanceOf(address(allocator)), 500 finney);
        assertEq(yusdcAsset.vault().balanceOf(address(allocator)), 500 finney);
        assertEq(yusdtAsset.vault().balanceOf(address(allocator)), 500 finney);

        // this will never be anyone other than 0
        assertEq(elf.balance(), 2 ether);

        // Deposit 3
        user3.approve(address(weth), address(elf));
        user3.call_deposit(address(elf), 1 ether);
        assertEq(weth.balanceOf(address(user3)), 999 ether);

        assertEq(elf.totalSupply(), 3 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(allocator)), 0 ether);

        // ensure WETH is pushed to SPVs
        assertEq(weth.balanceOf(address(spv1)), 750 finney);
        assertEq(weth.balanceOf(address(spv2)), 750 finney);
        assertEq(weth.balanceOf(address(spv3)), 750 finney);
        assertEq(weth.balanceOf(address(spv4)), 750 finney);

        // ensure assets hold borrowed assets
        assertEq(ydaiAsset.vault().balanceOf(address(allocator)), 750 finney);
        assertEq(ytusdAsset.vault().balanceOf(address(allocator)), 750 finney);
        assertEq(yusdcAsset.vault().balanceOf(address(allocator)), 750 finney);
        assertEq(yusdtAsset.vault().balanceOf(address(allocator)), 750 finney);

        // this will never be anyone other than 0
        assertEq(elf.balance(), 3 ether);
    }

    function test_multipleWETHDepositsAndWithdraws() public {
        // verify starting balance
        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);

        uint256 startingLenderTokenBalance = 10000000 ether;
        assertEq(dai.balanceOf(address(spv1)), startingLenderTokenBalance);
        assertEq(tusd.balanceOf(address(spv2)), startingLenderTokenBalance);
        assertEq(usdc.balanceOf(address(spv3)), startingLenderTokenBalance);
        assertEq(usdt.balanceOf(address(spv4)), startingLenderTokenBalance);

        // 3 approvals
        user1.approve(address(weth), address(elf));
        user2.approve(address(weth), address(elf));
        user3.approve(address(weth), address(elf));

        // 3 deposits
        user1.call_deposit(address(elf), 1 ether);
        user2.call_deposit(address(elf), 1 ether);
        user3.call_deposit(address(elf), 1 ether);

        assertEq(weth.balanceOf(address(user1)), 999 ether);
        assertEq(weth.balanceOf(address(user2)), 999 ether);
        assertEq(weth.balanceOf(address(user3)), 999 ether);

        assertEq(elf.totalSupply(), 3 ether);

        assertEq(weth.balanceOf(address(spv1)), 750 finney);
        assertEq(weth.balanceOf(address(spv2)), 750 finney);
        assertEq(weth.balanceOf(address(spv3)), 750 finney);
        assertEq(weth.balanceOf(address(spv4)), 750 finney);

        assertEq(ydaiAsset.vault().balanceOf(address(allocator)), 750 finney);
        assertEq(ytusdAsset.vault().balanceOf(address(allocator)), 750 finney);
        assertEq(yusdcAsset.vault().balanceOf(address(allocator)), 750 finney);
        assertEq(yusdtAsset.vault().balanceOf(address(allocator)), 750 finney);

        assertEq(ydaiAsset.balance(), 750 finney);
        assertEq(ytusdAsset.balance(), 750 finney);
        assertEq(yusdcAsset.balance(), 750 finney);
        assertEq(yusdtAsset.balance(), 750 finney);

        assertEq(dai.balanceOf(address(ydaiAsset)), 0);
        assertEq(dai.balanceOf(address(ytusdAsset)), 0);
        assertEq(dai.balanceOf(address(yusdcAsset)), 0);
        assertEq(dai.balanceOf(address(yusdtAsset)), 0);

        // 3 withdraws
        user1.call_withdraw(address(elf), 1 ether);
        user2.call_withdraw(address(elf), 1 ether);
        user3.call_withdraw(address(elf), 1 ether);

        assertEq(elf.totalSupply(), 0 ether);
        assertEq(weth.balanceOf(address(allocator)), 0 ether);

        assertEq(weth.balanceOf(address(spv1)), 0 ether);
        assertEq(weth.balanceOf(address(spv2)), 0 ether);
        assertEq(weth.balanceOf(address(spv3)), 0 ether);
        assertEq(weth.balanceOf(address(spv4)), 0 ether);

        assertEq(dai.balanceOf(address(spv1)), startingLenderTokenBalance);
        assertEq(tusd.balanceOf(address(spv2)), startingLenderTokenBalance);
        assertEq(usdc.balanceOf(address(spv3)), startingLenderTokenBalance);
        assertEq(usdt.balanceOf(address(spv4)), startingLenderTokenBalance);

        // validate ending balance
        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);
    }

    function test_multipleETHDepositsAndWithdraws() public {
        // verify starting balance
        assertEq(address(user1).balance, 1000 ether);
        assertEq(address(user2).balance, 1000 ether);
        assertEq(address(user3).balance, 1000 ether);

        uint256 startingLenderTokenBalance = 10000000 ether;
        assertEq(dai.balanceOf(address(spv1)), startingLenderTokenBalance);
        assertEq(tusd.balanceOf(address(spv2)), startingLenderTokenBalance);
        assertEq(usdc.balanceOf(address(spv3)), startingLenderTokenBalance);
        assertEq(usdt.balanceOf(address(spv4)), startingLenderTokenBalance);

        // 3 deposits
        user1.call_depositETH(address(elf), 1 ether);
        user2.call_depositETH(address(elf), 1 ether);
        user3.call_depositETH(address(elf), 1 ether);

        assertEq(address(user1).balance, 999 ether);
        assertEq(address(user2).balance, 999 ether);
        assertEq(address(user3).balance, 999 ether);

        assertEq(elf.totalSupply(), 3 ether);

        assertEq(weth.balanceOf(address(spv1)), 750 finney);
        assertEq(weth.balanceOf(address(spv2)), 750 finney);
        assertEq(weth.balanceOf(address(spv3)), 750 finney);
        assertEq(weth.balanceOf(address(spv4)), 750 finney);

        assertEq(ydaiAsset.vault().balanceOf(address(allocator)), 750 finney);
        assertEq(ytusdAsset.vault().balanceOf(address(allocator)), 750 finney);
        assertEq(yusdcAsset.vault().balanceOf(address(allocator)), 750 finney);
        assertEq(yusdtAsset.vault().balanceOf(address(allocator)), 750 finney);

        assertEq(ydaiAsset.balance(), 750 finney);
        assertEq(ytusdAsset.balance(), 750 finney);
        assertEq(yusdcAsset.balance(), 750 finney);
        assertEq(yusdtAsset.balance(), 750 finney);

        assertEq(dai.balanceOf(address(ydaiAsset)), 0);
        assertEq(dai.balanceOf(address(ytusdAsset)), 0);
        assertEq(dai.balanceOf(address(yusdcAsset)), 0);
        assertEq(dai.balanceOf(address(yusdtAsset)), 0);

        // 3 withdraws
        user1.call_withdrawETH(address(elf), 1 ether);
        user2.call_withdrawETH(address(elf), 1 ether);
        user3.call_withdrawETH(address(elf), 1 ether);

        assertEq(elf.totalSupply(), 0 ether);
        assertEq(weth.balanceOf(address(allocator)), 0 ether);

        assertEq(weth.balanceOf(address(spv1)), 0 ether);
        assertEq(weth.balanceOf(address(spv2)), 0 ether);
        assertEq(weth.balanceOf(address(spv3)), 0 ether);
        assertEq(weth.balanceOf(address(spv4)), 0 ether);

        assertEq(dai.balanceOf(address(spv1)), startingLenderTokenBalance);
        assertEq(tusd.balanceOf(address(spv2)), startingLenderTokenBalance);
        assertEq(usdc.balanceOf(address(spv3)), startingLenderTokenBalance);
        assertEq(usdt.balanceOf(address(spv4)), startingLenderTokenBalance);

        // validate ending balance
        assertEq(address(user1).balance, 1000 ether);
        assertEq(address(user2).balance, 1000 ether);
        assertEq(address(user3).balance, 1000 ether);
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }

    // require for withdraw tests to work
    receive() external payable {}
}
