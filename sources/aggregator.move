module kana_aggregator::aggregate {
    use aptos_framework::coin;
    use aptos_framework::account;
    use std::signer;
    use std::option;
    use std::option::{Option, is_some, borrow};
    use aptos_std::event::EventHandle;
    use aptos_framework::timestamp;
    use aptos_std::event;
    use aptos_std::type_info::{TypeInfo,type_of};
    use liquidswap::router;

  const HI_64: u64 = 0xffffffffffffffff;

    const E_UNKNOWN_POOL_TYPE: u64 = 1;
    const E_OUTPUT_LESS_THAN_MINIMUM: u64 = 2;
    const E_UNKNOWN_DEX: u64 = 3;
    const E_NOT_ADMIN: u64 = 4;
       const DEX_PONTEM: u8 = 1;
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
        // is_x_to_y: bool,
        x_in: coin::Coin<X>,
        y_min_out: u64
    ): (Option<coin::Coin<X>>, coin::Coin<Y>) acquires EventStore {
        let coin_in_value = coin::value(&x_in);
        let (x_out_opt, y_out) =
         if (dex_type == DEX_PONTEM) {

            (option::none(), router::swap_exact_coin_for_coin<X, Y, E>(x_in, y_min_out))
        }
        else {
            abort E_UNKNOWN_DEX
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
      public fun direct_impl<X, Y, E>(
        dex_type: u8,
        pool_type: u64,
        // is_x_to_y: bool,
        x_in: coin::Coin<X>,
        y_min_out: u64
    ):(Option<coin::Coin<X>>, coin::Coin<Y>) acquires EventStore {
        get_intermediate_output<X, Y, E>(dex_type, pool_type,  x_in,y_min_out)
    }

    
 public entry fun direct_route<X, Y, E>(
        sender: &signer,
        first_dex_type: u8,
        first_pool_type: u64,
        // first_is_x_to_y: bool, // first trade uses normal order
        x_in: u64,
        y_min_out: u64,
    ) acquires EventStore {
        let coin_in = coin::withdraw<X>(sender, x_in);
        let (coin_remain_opt, coin_out) = direct_impl<X, Y, E>(first_dex_type, first_pool_type, coin_in,y_min_out);
        assert!(coin::value(&coin_out) >= y_min_out, E_OUTPUT_LESS_THAN_MINIMUM);
        check_and_deposit_opt(sender, coin_remain_opt);
        check_and_deposit(sender, coin_out);
    }


}