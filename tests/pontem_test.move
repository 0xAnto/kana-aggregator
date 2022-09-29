// #[test_only]
// module kana_aggregator::hippo {
//     use std::debug;
//     use std::signer;
//     use aptos_framework::aptos_account;
//     use aptos_framework::coin;
//     use aptos_framework::genesis;

//     use kana_aggregator::aggregator::{one_step_route, init_module_test};
//     use test_coins::coins::{USDT, BTC};

//     #[test_only]
//     struct E1{}

//     #[test_only]
//     const DEX_PONTEM: u8 = 1;


//     #[test(aggregator = @kana_aggregator, liquid_swap = @liquid_swap, coin_list_admin = @coin_list, user=@0x67676)]
//     fun test_one_step_hippo(aggregator: &signer, liquid_swap: &signer, coin_list_admin: &signer, user: &signer){
//         genesis::setup();
//         aptos_account::create_account(signer::address_of(aggregator));
//         init_module_test(aggregator);
//         if (signer::address_of(liquid_swap) != signer::address_of(aggregator)) {
//             aptos_account::create_account(signer::address_of(liquid_swap));
//         };
//         debug::print(coin_list_admin);
//         let btc_coins_to_swap = 100;

//         let user_addr = signer::address_of(user);
//         let btc_coins_to_swap = test_coins::mint<BTC>(&coin_admin, btc_coins_swap_val);
//         assert!(coin::balance<BTC>(user_addr) == btc_coins_to_swap, 0);
//         one_step_route<BTC, USDT, E1>(
//             user,
//             DEX_PONTEM,
//             (HIPPO_CONSTANT_PRODUCT as u64),
//             // true,
//             btc_coins_to_swap,
//             0
//         );
//         // assert!(coin::balance<BTC>(user_addr) == 0, 0);
//         // debug::print(&coin::balance<USDT>(user_addr));
//         // assert!(coin::balance<USDT>(user_addr) > 0,0 )
//     }
// }