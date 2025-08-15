# RuleBook

<!-- RULEBOOK:INTRO:START -->

A lightweight, deterministic forward-chaining rules engine for Elixir.

RuleBook lets you declare rules over your domain facts using Elixir pattern matching and guards.
It unifies variables across patterns, builds an agenda of activations, and executes pure actions
that return effects (assert, retract, emit, log). Your application applies these effects; in
particular, emitted events are your responsibility to observe and handle.

Key concepts:

- Rule module: a module that `use`s `RuleBook.Rules` and defines `defrule` clauses.
- Fact: any Elixir term asserted into the working memory.
- Pattern: a struct/map pattern used in `when: [...]`; can have guards (`when ...`).
- Binding: variables bound by patterns and unified across them.
- Agenda: ordered list of activations ready to fire based on salience (priority).
- Activation: a specific rule with a concrete set of bindings.
- Effects: pure descriptions of changes (assert/retract), logs, or emitted events.

Actions should be pure functions that return effects using `RuleBook.Action` helpers.

<!-- RULEBOOK:INTRO:END -->

## Installation

Add to your mix deps:

```elixir
{:rule_book, "~> 0.1.0"}
```

## Quick start

```elixir
defmodule FraudRules do
  use RuleBook.DSL

  defmodule User do
    defstruct [:id, :country]
  end

  defmodule Payment do
    defstruct [:id, :user_id, :amount, :country]
  end

  defmodule Decision do
    defstruct [:payment_id, :status, :reason]
  end

  # Block payment when the user's country differs from the payment country
  defrule :block_if_country_mismatch,
    when: [
      %Payment{id: payment_id, user_id: uid, country: pay_country},
      %User{id: uid, country: user_country} when pay_country != user_country
    ],
    then: fn ctx ->
      b = ctx.binding
      RuleBook.Action.assert(ctx, %Decision{
        payment_id: b.payment_id,
        status: :blocked,
        reason: :country_mismatch
      })
    end,
    salience: 10
end

# 1) Get facts (user, payment)
user = %FraudRules.User{id: 1, country: :US}
payment = %FraudRules.Payment{id: 10, user_id: 1, amount: 125_00, country: :DE}

# 2) Run rules
{:ok, rb} = RuleBook.new(rules: FraudRules)
rb = rb |> RuleBook.assert(user) |> RuleBook.assert(payment)
{rb, _acts} = RuleBook.run(rb)

# 3) Decide: allow if no blocking decision, otherwise block
blocked? =
  RuleBook.facts(rb)
  |> Enum.any?(fn
    %FraudRules.Decision{payment_id: ^payment.id, status: :blocked} -> true
    _ -> false
  end)

case blocked? do
  true -> :block
  false -> :allow
end
```

## Guards and unification

You can compare values across different facts using guards and shared variable names:

```elixir
defrule :country_mismatch,
  when: [
    %Payment{user_id: uid, country: pay_country},
    %User{id: uid, country: user_country} when pay_country != user_country
  ],
  then: fn ctx -> ctx end
```
