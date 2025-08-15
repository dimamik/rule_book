# RuleBook

[![CI](https://github.com/dimamik/rule_book/actions/workflows/ci.yml/badge.svg)](https://github.com/dimamik/rule_book/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/rule_book.svg)](https://github.com/dimamik/rule_book/blob/main/LICENSE)
[![Version](https://img.shields.io/hexpm/v/rule_book.svg)](https://hex.pm/packages/rule_book)
[![Hex Docs](https://img.shields.io/badge/documentation-gray.svg)](https://hexdocs.pm/rule_book)

<!-- MDOC -->

A lightweight, deterministic [forward-chaining](https://en.wikipedia.org/wiki/Forward_chaining) rules engine for Elixir.

## Usage

```elixir
defmodule FraudRules do
  use RuleBook.Rules

  defmodule User do
    defstruct [:id, :country]
  end

  defmodule Payment do
    defstruct [:id, :user_id, :amount, :country]
  end

  defmodule Decision do
    defstruct [:payment_id, :status, :reason]
  end

  @doc "Block payment when the user's country differs from the payment country"
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

# 1) Facts (user, payment) -> Fetch them from the db or infer from the context
user = %FraudRules.User{id: 1, country: :US}
payment = %FraudRules.Payment{id: 10, user_id: 1, amount: 12_500, country: :DE}

# 2) Run rules
rule_book = RuleBook.new(rules: FraudRules)
rule_book = rule_book |> RuleBook.assert(user) |> RuleBook.assert(payment)
{_rule_book, acts} = RuleBook.run(rb)

# 3) Decide: allow if no blocking decision, otherwise block
rb
|> RuleBook.facts()
|> Enum.any?(fn
  %FraudRules.Decision{payment_id: ^payment.id, status: :blocked} -> true
  _ -> false
end)
|> case do
  # At least one rule matched to block the payment
  true -> :block
  # No rules matched to block the payment
  false -> :allow
end
```

## Why RuleBook?

Write rules with Elixir’s pattern matching and guards. RuleBook unifies variables across patterns,
builds an ordered agenda, and executes pure actions that return effects (assert, retract, emit, log).
Your app applies those effects; in particular, emitted events are your responsibility to observe.

Key ideas: rules, facts, patterns (+ guards), bindings (unified variables), agenda, activations, effects.
Actions should be pure; use `RuleBook.Action` helpers to return effects.

## Concepts

- **Rule module** — a plain Elixir module that `use`s `RuleBook.Rules` and declares rules with `defrule`.
- **Rule** — a named rule with a `when:` clause (patterns + optional guards) and a `then:` action that returns effects; may set `salience` and `mode`.
- **Pattern** — a struct or map pattern matched against facts; can add constraints with guards via `when`.
- **Guard** — an Elixir guard expression evaluated with the current bindings; lets you relate values across different patterns.
- **Binding** — a map of variables bound by patterns; shared names unify across patterns and are available to actions as `ctx.binding`.
- **Fact** — any Elixir term asserted into working memory (e.g., via `RuleBook.assert/2`); matched by patterns until retracted.
- **Agenda** — a deterministic, ordered queue of activations ready to fire, sorted primarily by `salience`.
- **Activation** — a scheduled firing of a rule with a concrete set of bindings (a specific match of facts).
- **Action** — a pure function receiving `%{rb, binding, effects}` and returning new effects; keep side effects out of actions.
- **Effects** — pure descriptions of changes for the host app to apply: `assert/2`, `retract/2`, `emit/3`, `log/3`.
- **Salience** — an integer priority for rules; higher values schedule earlier when building the agenda.
- **Once/mode** — controls how often a rule fires: `:once` fires at most once; `:per_fact` fires for each distinct binding/fact set.

## Telemetry

RuleBook (in the future) will emit telemetry when building the agenda, firing activations, and applying memory changes.
Events use the `[:rule_book, ...]` prefix and are no-ops unless `:telemetry` is available.

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

<!-- MDOC -->

## Install

```elixir
{:rule_book, "~> 0.1.0"}
```
