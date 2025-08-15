defmodule RuleBook.DSL do
  @moduledoc """
  DEPRECATED: Use `RuleBook.Rules` instead. This module re-exports `defrule` for backward compatibility.
  """

  defmacro __using__(_opts) do
    quote do
      import RuleBook.Rules, only: [defrule: 2]
      Module.register_attribute(__MODULE__, :__rulebook_rules__, accumulate: true)
      @before_compile RuleBook.Rules
    end
  end
end
