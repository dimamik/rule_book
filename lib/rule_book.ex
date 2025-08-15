defmodule RuleBook do
  @external_resource readme = Path.join([__DIR__, "../README.md"])

  @moduledoc readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  alias RuleBook.Engine
  alias RuleBook.Types

  @typedoc "A fact is any Elixir term"
  @type fact :: term()
  @typedoc "Fact identifier"
  @type fact_id :: any()
  @typedoc "Bindings map populated by matchers"
  @type binding :: map()
  @typedoc "Activation entry"
  @type activation :: %{rule: atom(), bindings: binding(), salience: integer()}

  defstruct rules: [],
            memory: nil,
            agenda: [],
            metrics: %{},
            options: %{},
            # tokens: activations fired in current memory state (prevents immediate re-fire)
            tokens: MapSet.new(),
            # once_tokens: activations for rules declared as once (persist across memory changes)
            once_tokens: MapSet.new()

  @type t :: %__MODULE__{
          rules: [Types.Rule.t()],
          memory: Engine.Memory.t(),
          agenda: [activation()],
          metrics: map(),
          options: map(),
          tokens: MapSet.t(),
          once_tokens: MapSet.t()
        }

  @doc """
  Create a new RuleBook session.

  Options:
    * `:rules` - a module using `RuleBook.DSL` or a list of such modules
    * `:pure` - when true, actions return effects without applying them
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    rules_mods = List.wrap(Keyword.get(opts, :rules, []))
    rules = Enum.flat_map(rules_mods, &compile_rules/1)
    memory = Engine.Memory.new()
    %__MODULE__{rules: rules, memory: memory, options: Map.new(opts)}
  end

  defp compile_rules(mod) when is_atom(mod) do
    if function_exported?(mod, :__rulebook_rules__, 0) do
      mod.__rulebook_rules__()
    else
      raise ArgumentError, "#{inspect(mod)} does not define any rules. Use RuleBook.Rules"
    end
  end

  @doc "Assert a fact into working memory."
  @spec assert(t(), fact()) :: t()
  def assert(%__MODULE__{} = rb, fact) do
    {memory, changed_ids} = Engine.Memory.assert(rb.memory, fact)
    # Keep tokens to avoid re-firing the same activation when asserting new facts
    # from within an action. We'll still rebuild the agenda to include any new activations.
    rb = %__MODULE__{rb | memory: memory}
    recompute_agenda(rb, changed_ids)
  end

  @doc "Retract a fact by id or by value."
  @spec retract(t(), fact_id() | fact()) :: t()
  def retract(%__MODULE__{} = rb, id_or_fact) do
    {memory, changed_ids} = Engine.Memory.retract(rb.memory, id_or_fact)
    # Do not clear tokens globally; the removed activations will not be rebuilt anyway.
    rb = %__MODULE__{rb | memory: memory}
    recompute_agenda(rb, changed_ids)
  end

  @doc "Insert or update a fact. If equal, no-op."
  @spec upsert(t(), fact()) :: t()
  def upsert(%__MODULE__{} = rb, fact) do
    {memory, changed_ids} = Engine.Memory.upsert(rb.memory, fact)
    # Keep tokens to avoid unnecessary re-firing on updates.
    rb = %__MODULE__{rb | memory: memory}
    recompute_agenda(rb, changed_ids)
  end

  @doc false
  @spec apply_effect(t(), {:assert, fact()} | {:retract, fact_id() | fact()} | {:upsert, fact()}) ::
          t()
  def apply_effect(%__MODULE__{} = rb, {:assert, fact}) do
    {memory, changed_ids} = Engine.Memory.assert(rb.memory, fact)
    rb = %__MODULE__{rb | memory: memory}
    recompute_agenda(rb, changed_ids)
  end

  def apply_effect(%__MODULE__{} = rb, {:retract, id_or_fact}) do
    {memory, changed_ids} = Engine.Memory.retract(rb.memory, id_or_fact)
    rb = %__MODULE__{rb | memory: memory}
    recompute_agenda(rb, changed_ids)
  end

  def apply_effect(%__MODULE__{} = rb, {:upsert, fact}) do
    {memory, changed_ids} = Engine.Memory.upsert(rb.memory, fact)
    rb = %__MODULE__{rb | memory: memory}
    recompute_agenda(rb, changed_ids)
  end

  @doc "Run until no activations remain or until `:max_steps` reached. Returns updated rb and the list of fired activations."
  @spec run(t(), keyword()) :: {t(), [activation()]}
  def run(%__MODULE__{} = rb, opts \\ []) do
    max_steps = Keyword.get(opts, :max_steps, :infinity)
    do_run(rb, max_steps, [])
  end

  defp do_run(rb, 0, fired), do: {rb, Enum.reverse(fired)}

  defp do_run(%__MODULE__{} = rb, max_steps, fired) do
    case step(rb) do
      {rb, :none} ->
        {rb, Enum.reverse(fired)}

      {rb, act} ->
        steps_left = if max_steps == :infinity, do: :infinity, else: max_steps - 1
        do_run(rb, steps_left, [act | fired])
    end
  end

  @doc "Fire one activation from the agenda, if any."
  @spec step(t()) :: {t(), activation() | :none}
  def step(%__MODULE__{} = rb) do
    case rb.agenda do
      [] ->
        {rb, :none}

      [act | rest] ->
        {rb2, _effects} = Engine.fire_activation(%{rb | agenda: rest}, act)
        rb3 = recompute_agenda(rb2, :all)
        {rb3, act}
    end
  end

  @doc "Get current agenda."
  @spec agenda(t()) :: [activation()]
  def agenda(%__MODULE__{} = rb), do: rb.agenda

  @doc "Enumerate facts."
  @spec facts(t()) :: Enumerable.t()
  def facts(%__MODULE__{} = rb), do: Engine.Memory.facts(rb.memory)

  @doc "Return metrics map."
  @spec metrics(t()) :: map()
  def metrics(%__MODULE__{} = rb), do: rb.metrics

  defp recompute_agenda(%__MODULE__{} = rb, changed_ids) do
    agenda =
      Engine.build_agenda(
        rb.rules,
        rb.memory,
        rb.tokens,
        rb.once_tokens,
        changed_ids,
        rb.options
      )

    %__MODULE__{rb | agenda: agenda}
  end
end
