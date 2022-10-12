module kana_aggregator::aggregator {
    use aptos_framework::coin;
    use aptos_framework::account;
    use std::signer;
    use std::option;
    use std::option::{Option, is_some, borrow};
    use aptos_std::event::EventHandle;
    use aptos_framework::timestamp;
    use aptos_std::event;
    use aptos_std::type_info::{TypeInfo, type_of};
    // use pontem::router;
    // use liquidswap::curves::Uncorrelated;
    // use test_coins::coins::{USDT, BTC};

    const HI_64: u64 = 0xffffffffffffffff;

    const E_UNKNOWN_POOL_TYPE: u64 = 1;
    const E_OUTPUT_LESS_THAN_MINIMUM: u64 = 2;
    const E_UNKNOWN_DEX: u64 = 3;
    const E_NOT_ADMIN: u64 = 4;
    
    
    const DEX_PONTEM: u8 = 1;
    const DEX_BASIQ: u8 = 2;
 struct EventStore has key {
        swap_step_events: EventHandle<SwapStepEvent>,
    }

    struct SwapStepEvent has drop, store {
        dex_type: u8,
        pool_type: u64,
        // input coin type
        x_type_info: TypeInfo,
        // output coin type
        y_type_info: TypeInfo,
        input_amount: u64,
        output_amount: u64,
        time_stamp: u64
    }

     entry fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @kana_aggregator, E_NOT_ADMIN);
        move_to(admin, EventStore {
            swap_step_events: account::new_event_handle<SwapStepEvent>(admin)
        });
    }

    #[test_only]
    public fun init_module_test(admin: &signer) {
        init_module(admin);
    }

    fun emit_swap_step_event<Input, Output>(
        dex_type:u8,
        pool_type:u64,
        input_amount:u64,
        output_amount: u64
    ) acquires EventStore {
        let event_store = borrow_global_mut<EventStore>(@kana_aggregator);
        event::emit_event<SwapStepEvent>(
            &mut event_store.swap_step_events,
            SwapStepEvent {
                dex_type,
                pool_type,
                x_type_info: type_of<coin::Coin<Input>>(),
                y_type_info: type_of<coin::Coin<Output>>(),
                input_amount,
                output_amount,
                time_stamp: timestamp::now_microseconds()
            },
        );
    }

      public fun get_intermediate_output<X, Y, E>(
        dex_type: u8,
        pool_type: u64,
        is_x_to_y: bool,
        x_in: coin::Coin<X>,
    ): (Option<coin::Coin<X>>, coin::Coin<Y>) acquires EventStore {
        let coin_in_value = coin::value(&x_in);
        let (x_out_opt, y_out) =   if (dex_type == DEX_BASIQ) {
            use basiq::dex;
            (option::none(), dex::swap<X, Y>(x_in))
        }
        else if (dex_type == DEX_PONTEM) {
            use pontem::router;
            (option::none(), router::swap_exact_coin_for_coin<X, Y, E>(@kana_aggregator, x_in, 0))
        }
        else {
            if(is_x_to_y){
            abort E_UNKNOWN_DEX
            } else {
            abort E_UNKNOWN_DEX

            }
        };

        let coin_in_value = if (is_some(&x_out_opt)) {
            coin_in_value - coin::value(borrow(&x_out_opt))
        } else {
            coin_in_value
        };
        emit_swap_step_event<X, Y>(
            dex_type,
            pool_type,
            coin_in_value,
            coin::value(&y_out)
        );
        (x_out_opt, y_out)
    }
  fun check_and_deposit_opt<X>(sender: &signer, coin_opt: Option<coin::Coin<X>>) {
        if (option::is_some(&coin_opt)) {
            let coin = option::extract(&mut coin_opt);
            let sender_addr = signer::address_of(sender);
            if (!coin::is_account_registered<X>(sender_addr)) {
                coin::register<X>(sender);
            };
            coin::deposit(sender_addr, coin);
        };
        option::destroy_none(coin_opt)
    }

    fun check_and_deposit<X>(sender: &signer, coin: coin::Coin<X>) {
        let sender_addr = signer::address_of(sender);
        if (!coin::is_account_registered<X>(sender_addr)) {
            coin::register<X>(sender);
        };
        coin::deposit(sender_addr, coin);
    }
      public fun one_step_direct<X, Y, E>(
        dex_type: u8,
        pool_type: u64,
        is_x_to_y: bool,
        x_in: coin::Coin<X>,
    ):(Option<coin::Coin<X>>, coin::Coin<Y>) acquires EventStore {
        get_intermediate_output<X, Y, E>(dex_type, pool_type, is_x_to_y, x_in)
    }
 public entry fun one_step_route<X, Y, E>(
        sender: &signer,
        first_dex_type: u8,
        first_pool_type: u64,
        first_is_x_to_y: bool, // first trade uses normal order
        x_in: u64,
        y_min_out: u64,
    ) acquires EventStore {
        let coin_in = coin::withdraw<X>(sender, x_in);
        // let btc_coins_to_swap_val = router::get_amount_in<BTC, USDT, Uncorrelated>(y_min_out);
// let coin_in = coin::withdraw<BTC>(sender, btc_coins_to_swap_val);
        let (coin_remain_opt, coin_out) = one_step_direct<X, Y, E>(first_dex_type, first_pool_type, first_is_x_to_y, coin_in);
        assert!(coin::value(&coin_out) >= y_min_out, E_OUTPUT_LESS_THAN_MINIMUM);
        check_and_deposit_opt(sender, coin_remain_opt);
        check_and_deposit(sender, coin_out);
    }


}