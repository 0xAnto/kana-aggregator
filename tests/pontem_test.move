#[test_only]
module hippo_aggregator::pontem {
    use std::debug;
    use std::signer;
    use aptos_framework::aptos_account;
    use aptos_framework::coin;
    use aptos_framework::genesis;

    use hippo_aggregator::aggregator::{one_step_route, init_module_test};
    use pontem::router;
    use pontem::scripts;
    use pontem::lp::LP;
    // use pontem::curves::Uncorrelated;
    
    use coin_list::devnet_coins;
    use coin_list::coin_list;
    use coin_list::devnet_coins::{
        DevnetBTC as BTC,
        DevnetUSDC as USDC
    };

    #[test_only]
    struct E1{}

    #[test_only]
    const DEX_PONTEM: u8 = 1;
    #[test_only]
    const HIPPO_CONSTANT_PRODUCT:u8 = 1;

    #[test(aggregator = @kana_aggregator, pontem = @pontem, coin_list_admin = @coin_list, user=@user)]
    fun test_one_step_pontem(aggregator: &signer, pontem: &signer, coin_list_admin: &signer, user: &signer){
        genesis::setup();
        aptos_account::create_account(signer::address_of(aggregator));
        init_module_test(aggregator);
        if (signer::address_of(pontem) != signer::address_of(aggregator)) {
            aptos_account::create_account(signer::address_of(pontem));
        };

        coin_list::initialize(coin_list_admin);
        devnet_coins::deploy(coin_list_admin);
        scripts::register_pool_and_add_liquidity<BTC, USDC, LP>( aggregator,
            101,
            101,
            10100,
            10100,);
        let btc_amount = 100;
        devnet_coins::mint_to_wallet<BTC>(user, btc_amount);
        let user_addr = signer::address_of(user);
        assert!(coin::balance<BTC>(user_addr) == btc_amount, 0);
        one_step_route<BTC, USDC, E1>(
            user,
            DEX_PONTEM,
            (HIPPO_CONSTANT_PRODUCT as u64),
            true,
            100,
            0
        );

        assert!(coin::balance<BTC>(user_addr) == 0, 0);
        debug::print(&coin::balance<USDC>(user_addr));
        assert!(coin::balance<USDC>(user_addr) > 0,0 )
    }
}
