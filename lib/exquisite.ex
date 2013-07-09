#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                    Version 2, December 2004
#
#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
#
#  0. You just DO WHAT THE FUCK YOU WANT TO.

defmodule Exquisite do
  @type spec :: :ets.match_spec | :ets.compiled_match_spec

  @spec run(spec, tuple | [tuple]) :: { :ok, term } | { :error, term }
  def run(spec, what) when is_tuple(what) do
    if :ets.is_compiled_ms(spec) do
      run(spec, [what]) |> Enum.first
    else
      :ets.test_ms(what, spec)
    end
  end

  def run(spec, what) when is_list(what) do
    if :ets.is_compiled_ms(spec) do
      :ets.match_spec_run(what, spec)
    else
      case compile(spec) do
        { :ok, spec } ->
          :ets.match_spec_run(what, spec)

        { :error, _ } = e ->
          e
      end
    end
  end

  @spec run!(spec, tuple | [tuple]) :: term | no_return
  def run!(spec, what) when is_tuple(what) do
    case :ets.test_ms(what, spec) do
      { :ok, result } ->
        result

      { :error, reason } ->
        raise RuntimeError, message: reason
    end
  end

  def run!(spec, what) when is_list(what) do
    :ets.match_spec_run(what, :ets.match_spec_compile(spec))
  end

  @spec compile(:ets.match_spec) :: { :ok, :ets.compiled_match_spec } | { :error, term }
  def compile(spec) do
    case :ets.test_ms({}, spec) do
      { :ok, _ } ->
        { :ok, :ets.match_spec_compile(spec) }

      { :error, _ } = e ->
        e
    end
  end

  @spec compile!(:ets.match_spec) :: :ets.compiled_match_spec | no_return
  def compile!(spec) do
    case compile(spec) do
      { :ok, spec } ->
        spec

      { :error, reason } ->
        raise SyntaxError, message: reason
    end
  end

  defmacrop execute(desc, rest) do
    quote do
      descriptor(unquote(desc), __CALLER__) |> transform(unquote(rest), __CALLER__) |> Macro.escape(unquote: true)
    end
  end

  @doc """
  I like trains.
  """
  defmacro match(clause, rest // [])

  # Exquisite.match a in Record, *
  defmacro match({ :in, _, [_, { :__aliases__, _, _ }] } = desc, rest) do
    execute(desc, rest)
  end

  # Exquisite.match a in { _, _, _ }, *
  defmacro match({ :in, _, [_, { :"{}", _, [_] }] } = desc, rest) do
    execute(desc, rest)
  end

  # Exquisite.match a in { _, _ }, *
  defmacro match({ :in, _, [_, { _, _ }] } = desc, rest) do
    execute(desc, rest)
  end

  # Exquisite.match { a, b, c }, *
  defmacro match({ :"{}", _, _ } = desc, rest) do
    execute(desc, rest)
  end

  # Exquisite.match { a, b }, *
  defmacro match({ _, _ } = desc, rest) do
    execute(desc, rest)
  end

  # Exquisite.match Record, *
  defmacro match({ :__aliases__, _, _ } = desc, rest) do
    execute(desc, rest)
  end

  defp descriptor({ :"{}", _, desc }, __CALLER__) do
    Enum.map desc, descriptor(&1, __CALLER__)
  end

  defp descriptor({ a, b }, __CALLER__) do
    [descriptor(a, __CALLER__), descriptor(b, __CALLER__)]
  end

  defp descriptor({ :in, _, [{ name, _, nil }, { :in, _, _ } = desc] }, __CALLER__) do
    { name, descriptor(desc, __CALLER__) }
  end

  defp descriptor({ :in, _, [{ name, _, nil }, { :__aliases__, _, _ } = record_alias] }, __CALLER__) do
    { name, descriptor(record_alias, __CALLER__) }
  end

  defp descriptor({ :in, _, [{ name, _, nil }, { :"{}", _, _ } = desc] }, __CALLER__) do
    { name, descriptor(desc, __CALLER__) }
  end

  defp descriptor({ :in, _, [{ name, _, nil }, { a, b }] }, __CALLER__) do
    { name, [descriptor(a, __CALLER__), descriptor(b, __CALLER__)] }
  end

  defp descriptor({ :__aliases__, _, _ } = record_alias, __CALLER__) do
    record_name   = Macro.expand(record_alias, __CALLER__)
    record_fields = Keyword.keys(record_name.__record__(:fields))

    { record_name, record_fields }
  end

  defp descriptor({ name, _, nil }, _) do
    name
  end

  defp transform(descriptor, clauses, __CALLER__) do
    { head, table } = head(descriptor)

    condition = if where = clauses[:where] do
      condition(where, table, __CALLER__)
    else
      []
    end

    body = if select = clauses[:select] do
      body(select, table, __CALLER__)
    else
      [:'$_']
    end

    [{ head, condition, body }]
  end

  defp head(descriptor) do
    case head(descriptor, HashDict.new, [], 1) do
      { result, table, _ } ->
        { result, table }
    end
  end

  defp head(descriptor, table, name, last) when is_list(descriptor) do
    { result, table, last } = Enum.reduce descriptor, { [], table, last }, fn(desc, { results, table, last }) ->
      case head(desc, table, name, last) do
        { result, table, last } ->
          { [result | results], table, last }
      end
    end

    { Enum.reverse(result) |> list_to_tuple, table, last }
  end

  defp head(descriptor, table, name, last) when is_atom(descriptor) do
    reference = :"$#{last}"

    { reference, Dict.put(table, name_for(descriptor, name), reference), last + 1 }
  end

  defp head({ atom, descriptor }, table, name, last) do
    cond do
      match?("Elixir." <> _, atom_to_binary(atom)) ->
        { result, table, last } = Enum.reduce descriptor, { [], table, last }, fn(desc, { results, table, last }) ->
          case head(desc, table, name, last) do
            { result, table, last } ->
              { [result | results], table, last }
          end
        end

        { [atom | Enum.reverse(result)] |> list_to_tuple, table, last }

      is_list(descriptor) ->
        { result, table, last } = Enum.reduce descriptor, { [], table, last }, fn(desc, { results, table, last }) ->
          case head(desc, table, [atom_to_binary(atom) | name], last) do
            { result, table, last } ->
              { [result | results], table, last }
          end
        end

        result = Enum.reverse(result) |> list_to_tuple
        table  = Dict.put(table, name_for(atom, name), result)

        { result, table, last }

      is_tuple(descriptor) ->
        case head(descriptor, table, [atom_to_binary(atom) | name], last) do
          { result, table, last } ->
            table = Dict.put(table, name_for(atom, name), result)

            { result, table, last }
        end
    end
  end

  defp name_for(new, current) do
    [atom_to_binary(new) | current] |> Enum.reverse |> Enum.join(".")
  end

  defp condition(clause, table, __CALLER__) do
    [internal(Macro.expand_all(clause, __CALLER__), table)]
  end

  defp body(clause, table, __CALLER__) do
    [internal(Macro.expand_all(clause, __CALLER__), table)]
  end

  # not
  defp internal({ :not, _, [a] }, table) do
    { :not, internal(a, table) }
  end

  # and, gets converted to andalso
  defp internal({ :and, _, [left, right] }, table) do
    { :andalso, internal(left, table), internal(right, table) }
  end

  # or, gets converted to orelse
  defp internal({ :or, _, [left, right] }, table) do
    { :orelse, internal(left, table), internal(right, table) }
  end

  # xor
  defp internal({ :xor, _, [left, right] }, table) do
    { :xor, internal(left, table), internal(right, table) }
  end

  # >
  defp internal({ :>, _, [left, right] }, table) do
    { :>, internal(left, table), internal(right, table) }
  end

  # >=
  defp internal({ :>=, _, [left, right] }, table) do
    { :>=, internal(left, table), internal(right, table) }
  end

  # <
  defp internal({ :<, _, [left, right] }, table) do
    { :<, internal(left, table), internal(right, table) }
  end

  # <=, gets converted to =<
  defp internal({ :<=, _, [left, right] }, table) do
    { :'=<', internal(left, table), internal(right, table) }
  end

  # ==
  defp internal({ :==, _, [left, right] }, table) do
    { :==, internal(left, table), internal(right, table) }
  end

  # ===, gets converted to =:=
  defp internal({ :===, _, [left, right] }, table) do
    { :'=:=', internal(left, table), internal(right, table) }
  end

  # != gets converted to /=
  defp internal({ :!=, _, [left, right] }, table) do
    { :'/=', internal(left, table), internal(right, table) }
  end

  # !== gets converted to =/=
  defp internal({ :!==, _, [left, right] }, table) do
    { :'=/=', internal(left, table), internal(right, table) }
  end

  # +
  defp internal({ :+, _, [left, right] }, table) do
    { :+, internal(left, table), internal(right, table) }
  end

  # -
  defp internal({ :-, _, [left, right] }, table) do
    { :-, internal(left, table), internal(right, table) }
  end

  # *
  defp internal({ :*, _, [left, right] }, table) do
    { :*, internal(left, table), internal(right, table) }
  end

  # /, gets converted to div
  defp internal({ :/, _, [left, right] }, table) do
    { :div, internal(left, table), internal(right, table) }
  end

  # rem
  defp internal({ :rem, _, [left, right] }, table) do
    { :rem, internal(left, table), internal(right, table) }
  end

  @function [ :is_atom, :is_float, :is_integer, :is_list, :is_number,
              :is_pid, :is_port, :is_reference, :is_tuple, :is_binary ]
  defp internal({ name, _, [ref] } = whole, table) when name in @function do
    if id = identify(ref, table) do
      { name, id }
    else
      external(whole)
    end
  end

  # is_record(id, name)
  defp internal({ :is_record, _, [ref, name] } = whole, table) do
    if id = identify(ref, table) do
      { :is_record, id, name, length(name.__record__(:fields)) + 1 }
    else
      external(whole)
    end
  end

  # is_record(id, name, size)
  defp internal({ :is_record, _, [ref, name, size] } = whole, table) do
    if id = identify(ref, table) do
      { :is_record, id, name, size }
    else
      external(whole)
    end
  end

  # elem(id, index)
  defp internal({ :elem, _, [ref, index] } = whole, table) do
    if id = identify(ref, table) do
      { :element, id, index + 1 }
    else
      external(whole)
    end
  end

  @function [ :abs, :hd, :length, :round, :tl, :trunc ]
  defp internal({ name, _, [ref] } = whole, table) when name in @function do
    if id = identify(ref, table) do
      { name, id }
    else
      external(whole)
    end
  end

  # bnot foo
  defp internal({ :bnot, _, [ref] } = whole, table) do
    if id = identify(ref, table) do
      { :bnot, id }
    else
      external(whole)
    end
  end

  @function [ :band, :bor, :bxor, :bsl, :bsr ]
  defp internal({ name, _, [left, right] }, table) when name in @function do
    { name, internal(left, table), internal(right, table) }
  end

  @function [ :node, :self ]
  defp internal({ name, _, [] }, _) when name in @function do
    { name }
  end

  # foo
  defp internal({ ref, _, nil } = whole, table) do
    if id = identify(ref, table) do
      id
    else
      external(whole)
    end
  end

  # foo.bar
  defp internal({{ :., _, _ }, _, _ } = whole, table) do
    if id = identify(whole, table) do
      id
    else
      external(whole)
    end
  end

  # { a, b }
  defp internal({ a, b }, table) do
    {{ internal(a, table), internal(b, table) }}
  end

  # { a, b, c }
  defp internal({ :'{}', _, desc }, table) do
    { Enum.map(desc, internal(&1, table)) |> list_to_tuple }
  end

  # list
  defp internal(value, table) when is_list(value) do
    Enum.map value, internal(&1, table)
  end

  # number or string
  defp internal(value, _) when is_binary(value) or is_number(value) do
    value
  end

  # otherwise just treat it as external
  defp internal(whole, _) do
    external(whole)
  end

  # identify a name from a table
  defp identify(name, table) do
    Dict.get(table, identify(name))
  end

  defp identify({{ :., _, [left, name] }, _, _ }) do
    identify(left) <> "." <> atom_to_binary(name)
  end

  defp identify({ name, _, _ }) do
    atom_to_binary(name)
  end

  defp identify(name) do
    atom_to_binary(name)
  end

  defp external(whole) do
    { :unquote, [], quote do: [Exquisite.convert(unquote(whole))] }
  end

  @doc false
  def convert(data) when is_tuple(data) do
    { tuple_to_list(data) |> Enum.map(convert(&1)) |> list_to_tuple }
  end

  def convert(data) when is_list(data) do
    Enum.map data, convert(&1)
  end

  def convert(data) do
    data
  end
end