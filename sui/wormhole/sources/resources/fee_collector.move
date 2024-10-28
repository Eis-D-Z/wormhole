// SPDX-License-Identifier: Apache 2

/// This module implements a container that collects fees in SUI denomination.
/// The `FeeCollector` requires that the fee deposited is exactly equal to the
/// `fee_amount` configured.
module wormhole::fee_collector {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};

    /// Amount deposited is not exactly the amount configured.
    const E_INCORRECT_FEE: u64 = 0;

    /// Container for configured `fee_amount` and `balance` of SUI collected.
    public struct FeeCollector has store {
        fee_amount: u64,
        balance: Balance<SUI>
    }

    /// Create new `FeeCollector` with specified amount to collect.
    public fun new(fee_amount: u64): FeeCollector {
        FeeCollector { fee_amount, balance: balance::zero() }
    }

    /// Retrieve configured amount to collect.
    public fun fee_amount(self: &FeeCollector): u64 {
        self.fee_amount
    }

    /// Retrieve current SUI balance.
    public fun balance_value(self: &FeeCollector): u64 {
        balance::value(&self.balance)
    }

    /// Take `Balance<SUI>` and add it to current collected balance.
    public fun deposit_balance(self: &mut FeeCollector, fee: Balance<SUI>) {
        assert!(balance::value(&fee) == self.fee_amount, E_INCORRECT_FEE);
        balance::join(&mut self.balance, fee);
    }

    /// Take `Coin<SUI>` and add it to current collected balance.
    public fun deposit(self: &mut FeeCollector, fee: Coin<SUI>) {
        deposit_balance(self, coin::into_balance(fee))
    }

    /// Create `Balance<SUI>` of some `amount` by taking from collected balance.
    public fun withdraw_balance(
        self: &mut FeeCollector,
        amount: u64
    ): Balance<SUI> {
        // This will trigger `sui::balance::ENotEnough` if amount > balance.
        balance::split(&mut self.balance, amount)
    }

    /// Create `Coin<SUI>` of some `amount` by taking from collected balance.
    public fun withdraw(
        self: &mut FeeCollector,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<SUI> {
        coin::from_balance(withdraw_balance(self, amount), ctx)
    }

    /// Re-configure current `fee_amount`.
    public fun change_fee(self: &mut FeeCollector, new_amount: u64) {
        self.fee_amount = new_amount;
    }

    #[test_only]
    public fun destroy(collector: FeeCollector) {
        let FeeCollector { fee_amount: _, balance: bal } = collector;
        balance::destroy_for_testing(bal);
    }
}

#[test_only]
module wormhole::fee_collector_tests {
    use sui::coin::{Self};

    use wormhole::fee_collector::{Self};

    #[test]
    public fun test_fee_collector() {
        let ctx = &mut tx_context::dummy();

        let fee_amount = 350;
        let mut collector = fee_collector::new(fee_amount);

        // We expect the fee_amount to be the same as what we specified and
        // no balance on `FeeCollector` yet.
        assert!(fee_collector::fee_amount(&collector) == fee_amount, 0);
        assert!(fee_collector::balance_value(&collector) == 0, 0);

        // Deposit fee once.
        let fee = coin::mint_for_testing(fee_amount, ctx);
        collector.deposit(fee);
        assert!(collector.balance_value() == fee_amount, 0);

        // Now deposit nine more times and check the aggregate balance.
        let mut i = 0;
        while (i < 9) {
            let fee = coin::mint_for_testing(fee_amount, ctx);
            collector.deposit(fee);
            i = i + 1;
        };
        let total = collector.balance_value();
        assert!(total == 10 * fee_amount, 0);

        // Withdraw a fifth.
        let withdraw_amount = total / 5;
        let withdrawn =
            collector.withdraw(withdraw_amount, ctx);
        assert!(withdrawn.value() == withdraw_amount, 0);
        withdrawn.burn_for_testing();

        let remaining = collector.balance_value();
        assert!(remaining == total - withdraw_amount, 0);

        // Withdraw remaining.
        let withdrawn = collector.withdraw(remaining, ctx);
        assert!(withdrawn.value() == remaining, 0);
        withdrawn.burn_for_testing();

        // There shouldn't be anything left in `FeeCollector`.
        assert!(collector.balance_value() == 0, 0);

        // Done.
        collector.destroy();
    }

    #[test]
    #[expected_failure(abort_code = fee_collector::E_INCORRECT_FEE)]
    public fun test_cannot_deposit_incorrect_fee() {
        let ctx = &mut tx_context::dummy();

        let fee_amount = 350;
        let mut collector = fee_collector::new(fee_amount);

        // You shall not pass!
        let fee = coin::mint_for_testing(fee_amount + 1, ctx);
        collector.deposit(fee);

        abort 42
    }

    #[test]
    #[expected_failure(abort_code = sui::balance::ENotEnough)]
    public fun test_cannot_withdraw_more_than_balance() {
        let ctx = &mut tx_context::dummy();

        let fee_amount = 350;
        let mut collector = fee_collector::new(fee_amount);

        // Deposit once.
        let fee = coin::mint_for_testing(fee_amount, ctx);
        collector.deposit(fee);

        // Attempt to withdraw more than the balance.
        let bal = collector.balance_value();
        let withdrawn =
            collector.withdraw(bal + 1, ctx);

        // Shouldn't get here. But we need to clean up anyway.
        withdrawn.burn_for_testing();

        abort 42
    }
}
