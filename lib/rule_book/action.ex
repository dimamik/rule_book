defmodule RuleBook.Action do
  @moduledoc """
  Helpers to build effects from actions. Actions receive a context map with keys:
  - :rb (the RuleBook session)
  - :binding (variables bound by matchers)
  - :effects (collected effects)
  """

  def emit(ctx, name, payload) do
    add_effect(ctx, {:emit, name, payload})
  end

  def assert(ctx, fact) do
    add_effect(ctx, {:assert, fact})
  end

  def retract(ctx, id_or_fact) do
    add_effect(ctx, {:retract, id_or_fact})
  end

  def log(ctx, level, msg) do
    add_effect(ctx, {:log, level, msg})
  end

  def set(ctx, key, value) do
    update_in(ctx[:effects], fn effs -> [{:set, key, value} | effs || []] end)
  end

  defp add_effect(ctx, eff), do: update_in(ctx[:effects], fn effs -> [eff | effs || []] end)
end
