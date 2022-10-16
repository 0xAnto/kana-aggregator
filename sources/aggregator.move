module kana_aggregator::aggregator {
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
    const DEX_APTOSWAP: u8 = 2;
    struct EventStore has key {
        swap_step_events: EventHandle<SwapStepEvent>,
    }

    struct SwapStepEvent has drop, store {
        dex_type: u8,
        pool_type: u64,
        x_type_info: TypeInfo,
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
        let (x_out_opt, y_out) =
         if (dex_type == DEX_PONTEM) {
            (option::none(), router::swap_exact_coin_for_coin<X, Y, E>(x_in, 0))
        }   
        else if (dex_type == DEX_APTOSWAP) {
            use Aptoswap::pool;
            if (is_x_to_y) {
                let y_out = pool::swap_x_to_y_direct<X, Y>(x_in);
                (option::none(), y_out)
            }
            else {
                let y_out = pool::swap_y_to_x_direct<Y, X>(x_in);
                (option::none(), y_out)
            }
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
        is_x_to_y: bool,
        x_in: coin::Coin<X>,
    ):(Option<coin::Coin<X>>, coin::Coin<Y>) acquires EventStore {
        get_intermediate_output<X, Y, E>(dex_type, pool_type, is_x_to_y, x_in)
    }

    
 public entry fun direct_route<X, Y, E>(
        sender: &signer,
        first_dex_type: u8,
        first_pool_type: u64,
        first_is_x_to_y: bool, // first trade uses normal order
        x_in: u64,
        y_min_out: u64,
    ) acquires EventStore {
        let coin_in = coin::withdraw<X>(sender, x_in);
        let (coin_remain_opt, coin_out) = direct_impl<X, Y, E>(first_dex_type, first_pool_type, first_is_x_to_y, coin_in);
        assert!(coin::value(&coin_out) >= y_min_out, E_OUTPUT_LESS_THAN_MINIMUM);
        check_and_deposit_opt(sender, coin_remain_opt);
        check_and_deposit(sender, coin_out);
    }
    public fun intermediate_route_impl<
            X, Y, Z, E1, E2,
        >(
        first_dex_type: u8,
        first_pool_type: u64,
        first_is_x_to_y: bool, // first trade uses normal order
        second_dex_type: u8,
        second_pool_type: u64,
        second_is_x_to_y: bool, // second trade uses normal order
        x_in: coin::Coin<X>
        ):(Option<coin::Coin<X>>, Option<coin::Coin<Y>>, coin::Coin<Z>) acquires EventStore {
            let (coin_x_remain, coin_y) = get_intermediate_output<X, Y, E1>(first_dex_type, first_pool_type, first_is_x_to_y, x_in);
            let (coin_y_remain, coin_z) = get_intermediate_output<Y, Z, E2>(second_dex_type, second_pool_type, second_is_x_to_y, coin_y);
            (coin_x_remain, coin_y_remain, coin_z)
    }
        #[cmd]
    public entry fun intermediate_route<
        X, Y, Z, E1, E2,
    >(
        sender: &signer,
        first_dex_type: u8,
        first_pool_type: u64,
        first_is_x_to_y: bool, // first trade uses normal order
        second_dex_type: u8,
        second_pool_type: u64,
        second_is_x_to_y: bool, // second trade uses normal order
        x_in: u64,
        z_min_out: u64,
    ) acquires EventStore {
        let coin_x = coin::withdraw<X>(sender, x_in);
        let (
            coin_x_remain,
            coin_y_remain,
            coin_z
        ) = intermediate_route_impl<X, Y, Z, E1, E2>(
            first_dex_type,
            first_pool_type,
            first_is_x_to_y,
            second_dex_type,
            second_pool_type,
            second_is_x_to_y,
            coin_x
        );
        assert!(coin::value(&coin_z) >= z_min_out, E_OUTPUT_LESS_THAN_MINIMUM);
        check_and_deposit_opt(sender, coin_x_remain);
        check_and_deposit_opt(sender, coin_y_remain);
        check_and_deposit(sender, coin_z);
    }


}