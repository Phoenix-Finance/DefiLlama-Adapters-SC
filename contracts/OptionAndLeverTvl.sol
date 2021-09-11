pragma solidity ^0.5.16;
import "./Math.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./Halt.sol";

interface IOptionFactory {
    function getOptionsMangerLength()external view returns (uint256);
    function getOptionsMangerAddress(uint256 index) external view returns (address,address,address,address);
    function vestingPool() external view returns (address);
    function phxOracle() external view returns (address);
}

interface IOptionManager {
    function getCollateralWhiteList() external view returns(address[] memory);
}

interface ILeverageFactory {
    function vestingPool() external view returns (address);
    function phxOracle() external view returns (address);
    function getAllStakePool()external view returns (address payable[] memory);
    function getAllLeveragePool()external view returns (address payable[] memory);
}

interface ILeverSakePool {
    function poolToken()external view returns (address);
}

interface ILeverPool {
    function getLeverageInfo() external view returns (address,address,address,uint256,uint256);
    function getHedgeInfo() external view returns (address,address,address,uint256,uint256);
    function getTotalworths() external view returns(uint256,uint256);
}

interface IOracle {
    function getPrice(address asset) external view returns (uint256);
}

contract OptionAndLeverTvl {
    using SafeMath for uint256;
    address public leverFactoryAddress;
    address public optionFactoryAddress;
    address public phxAddress;
    uint256 constant TLVMUL = 10**2;

    constructor(address _leverFactoryAddress,
                address _optionFactoryAddress,
                address _phxAddress) public {
        leverFactoryAddress = _leverFactoryAddress;
        optionFactoryAddress = _optionFactoryAddress;
        phxAddress = _phxAddress;
    }

    function getPriceTokenDecimal(address token) internal view returns(uint256){
        uint256 decimal = 10**18;
        if(token!=address(0)) {
            decimal = (10**IERC20(token).decimals());
        }
        return (uint256(10**18).div(decimal).mul(10**8)).mul(decimal).div(TLVMUL);
    }

    function getLeverStakePoolTvl()
        public
        view
        returns (uint256)
    {
        uint256 tvl = 0;
        address phxOracle = ILeverageFactory(leverFactoryAddress).phxOracle();
        address payable[] memory stakepools = ILeverageFactory(leverFactoryAddress).getAllStakePool();

        for(uint256 i=0;i<stakepools.length;i++) {
            address token = ILeverSakePool(stakepools[i]).poolToken();
            uint256 tokenPrice = IOracle(phxOracle).getPrice(token);
            uint256 tokenAmount = stakepools[i].balance;
            if(token!=address(0)) {
                tokenAmount = IERC20(token).balanceOf(stakepools[i]);
            }
            uint256 decimal = getPriceTokenDecimal(token);
            tvl = tvl.add(tokenAmount.mul(tokenPrice).div(decimal));
        }

        return tvl;
    }

    function getLeverPoolTvl()
        public
        view
        returns (uint256,uint256)
    {
        uint256 tvl = 0;
        address payable[] memory leverpools = ILeverageFactory(leverFactoryAddress).getAllLeveragePool();
        address phxOracle = ILeverageFactory(leverFactoryAddress).phxOracle();

        for(uint256 i=0;i<leverpools.length;i++) {

            address levertoken;
            address hedgetoken;
            (levertoken,,,,) = ILeverPool(leverpools[i]).getLeverageInfo();
            (hedgetoken,,,,) = ILeverPool(leverpools[i]).getHedgeInfo();

            uint256 leverTvl = IERC20(levertoken).balanceOf(leverpools[i]);
            uint256 price = IOracle(phxOracle).getPrice(levertoken);
            leverTvl = leverTvl.mul(price);
            uint256 leverdecimal = getPriceTokenDecimal(levertoken);
             tvl = tvl.add(leverTvl.div(leverdecimal));

           uint256 hedgeTvl = leverpools[i].balance;
           if(hedgetoken!=address(0)) {
               hedgeTvl = IERC20(hedgetoken).balanceOf(leverpools[i]);
           }

           price = IOracle(phxOracle).getPrice(hedgetoken);
           hedgeTvl = hedgeTvl.mul(price);
           uint256 hedgedecimal = getPriceTokenDecimal(hedgetoken);
           tvl = tvl.add(hedgeTvl.div(hedgedecimal));

        }

        return (tvl,leverpools.length);
    }

    function getPhxVestPoolTvl()
        public
        view
        returns (uint256)
    {
        address phxVestingPool = IOptionFactory(optionFactoryAddress).vestingPool();
        uint256 phxAmount = IERC20(phxAddress).balanceOf(phxVestingPool);
        address phxOracle = IOptionFactory(optionFactoryAddress).phxOracle();
        uint256 phxprice = IOracle(phxOracle).getPrice(phxAddress);
        uint256 decimal = getPriceTokenDecimal(phxAddress);
        return phxAmount.mul(phxprice).div(decimal);
    }

    function getOptionPoolTvl()
        public
        view
        returns (uint256)
    {
        uint256 len = IOptionFactory(optionFactoryAddress).getOptionsMangerLength();
        uint256 coltvl = 0;
        address phxOracle = IOptionFactory(optionFactoryAddress).phxOracle();
        for(uint256 i=0;i<len;i++) {
            address optionsManager;
            address collateral;
            (optionsManager,collateral,,) =  IOptionFactory(optionFactoryAddress).getOptionsMangerAddress(i);

            address[] memory tokens = IOptionManager(optionsManager).getCollateralWhiteList();
            for(uint256 j=0;j<tokens.length;j++) {
                uint256 amount = IERC20(tokens[j]).balanceOf(collateral);
                uint256 tkprice = IOracle(phxOracle).getPrice(tokens[i]);
                uint256 decimal = getPriceTokenDecimal(tokens[i]);
                coltvl=coltvl.add(amount.mul(tkprice).div(decimal));
            }
        }

        return coltvl;
    }

    function getTvl()
        public
        view
        returns (uint256)
    {
        uint256 leverstakepooltvl = getLeverStakePoolTvl();
        uint256 leverpooltvl;
        (leverpooltvl,) = getLeverPoolTvl();
        uint256 phxvestpooltvl = getPhxVestPoolTvl();
        uint256 optioncoltvl = getOptionPoolTvl();
        return leverstakepooltvl.add(leverpooltvl).add(phxvestpooltvl).add(optioncoltvl);
    }

}
