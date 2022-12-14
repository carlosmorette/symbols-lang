defmodule Symbols do
  def run(path) do
    File.read!(path)
    |> tokenize()
    |> parse()
    |> eval(new_env())
  end

  def tokenize(string_file) do
    string_file
    |> to_charlist()
    |> tokenize([], 1)
  end

  def tokenize([], tokens, line), do: tokens ++ [new_token(line, id: :EOF)]

  def tokenize([?# | rest], tokens, line) do
    tokenize(rest, tokens ++ [new_token(line, id: :HASHTAG)], line)
  end

  def tokenize([char | rest], tokens, line) when char in ?a..?z do
    {identifier, rest} = identifier(rest, [char])

    tokenize(
      rest,
      tokens ++ [new_token(line, id: :IDENTIFIER, value: to_string(identifier))],
      line
    )
  end

  def tokenize([char | rest], tokens, line) when char in ?0..?9 do
    {number, chars} = number(rest, [char])
    tokenize(chars, tokens ++ [new_token(line, id: :NUMBER, value: number)], line)
  end

  def tokenize([?$ | rest], tokens, line) do
    tokenize(rest, tokens ++ [new_token(line, id: :DOLLAR)], line)
  end

  def tokenize([?. | rest], tokens, line) do
    tokenize(rest, tokens ++ [new_token(line, id: :DOT)], line)
  end

  def tokenize([?@ | rest], tokens, line) do
    tokenize(rest, tokens ++ [new_token(line, id: :ARROBA)], line)
  end

  def tokenize([?& | rest], tokens, line) do
    {charlist_string, rest} = string(rest, [])

    tokenize(
      rest,
      tokens ++ [new_token(line, id: :STRING, value: to_string(charlist_string))],
      line
    )
  end

  def tokenize([?\n | rest], tokens, line) do
    tokenize(rest, tokens, line + 1)
  end

  def tokenize([?\s | rest], tokens, line) do
    tokenize(rest, tokens, line)
  end

  def tokenize([?! | rest], tokens, line) do
    tokenize(rest, tokens ++ [new_token(line, id: :EXCLAMATION)], line)
  end

  def tokenize([char | rest], tokens, line) when char in [?+, ?-, ?*, ?/] do
    t_id =
      case char do
        ?+ -> :PLUS
        ?- -> :MINUS
        ?* -> :STAR
        ?/ -> :SLASH
      end

    tokenize(rest, tokens ++ [new_token(line, id: t_id, value: <<char>>)], line)
  end

  def tokenize([c | _rest], _tokens, line) do
    raise "Dont't expected '#{<<c>>}', line: #{line}"
  end

  def identifier([], identifier), do: {identifier, []}

  def identifier([token | rest], acc) when token in ?a..?z do
    identifier(rest, acc ++ [token])
  end

  def identifier(tokens, identifier), do: {identifier, tokens}

  def string([?& | rest], acc) do
    {acc, rest}
  end

  def string([char | rest], acc) do
    string(rest, acc ++ [char])
  end

  def number([char | rest], acc) when char in ?0..?9 do
    number(rest, acc ++ [char])
  end

  def number(chars, acc) do
    {to_string(acc), chars}
  end

  def new_token(line, id: id, value: value) do
    %{id: id, value: value, line: line}
  end

  def new_token(line, id: id) do
    %{id: id, line: line}
  end

  # === Parsing ===

  def parse(tokens), do: parse_program(tokens, [])

  def parse_program([%{id: :EOF}], acc), do: acc

  def parse_program(tokens, acc) do
    {structure, tokens} =
      cond do
        match(tokens, :HASHTAG) ->
          {structure, tokens} = parse_decl_function(tokens)
          {structure, tokens}

        true ->
          {structure, tokens} = parse_expression(tokens)
          {structure, tokens}
      end

    parse_program(tokens, acc ++ [structure])
  end

  def parse_expression(tokens) do
    {tokens, print?} =
      if match(tokens, :EXCLAMATION) do
        {next(tokens), true}
      else
        {tokens, false}
      end

    cond do
      match(tokens, :DOLLAR) ->
        parse_fun_call(tokens, print?)

      true ->
        parse_literal(tokens)
    end
  end

  def parse_fun_call(tokens, print?) do
    tokens = expect(tokens, :DOLLAR)
    {fun_id, tokens} = expect_and_get(tokens, :IDENTIFIER)
    tokens = expect(tokens, :STAR)
    {params, tokens} = parse_call_fun_params(tokens)
    tokens = expect(tokens, :STAR)
    {%{type: :fun_call, id: fun_id, params: params, print: print?}, tokens}
  end

  def parse_call_fun_params(tokens, params \\ []) do
    cond do
      match(tokens, :STAR) ->
        {params, tokens}

      true ->
        {expr, tokens} = parse_expression(tokens)

        cond do
          match(tokens, :MINUS) ->
            parse_call_fun_params(next(tokens), params ++ [expr])

          match(tokens, :STAR) ->
            {params ++ [expr], tokens}
        end
    end
  end

  def parse_decl_function(tokens) do
    tokens = expect(tokens, :HASHTAG)
    {fun_id, tokens} = expect_and_get(tokens, :IDENTIFIER)
    {params, tokens} = parse_decl_fun_params(tokens)
    tokens = expect(tokens, :ARROBA)
    {body, tokens} = parse_fun_body(tokens)
    tokens = expect(tokens, :DOT)
    {%{type: :fun_decl, id: fun_id, params: params, body: body}, tokens}
  end

  def parse_decl_fun_params(tokens, params \\ []) do
    cond do
      match(tokens, :ARROBA) ->
        {params, tokens}

      match(tokens, :MINUS) ->
        {param_id, tokens} = expect_and_get(next(tokens), :IDENTIFIER)
        parse_decl_fun_params(tokens, params ++ [param_id])
    end
  end

  def parse_fun_body(tokens, expressions \\ []) do
    {structure, tokens} = parse_expression(tokens)

    cond do
      match(tokens, :MINUS) ->
        parse_fun_body(next(tokens), expressions ++ [structure])

      match(tokens, :DOT) ->
        {expressions ++ [structure], tokens}
    end
  end

  def parse_literal(tokens) do
    {literal, tokens} = get(tokens)
    {%{type: :literal, value: literal}, tokens}
  end

  def fun_call?([%{id: :DOLLAR} | _tokens]), do: true
  def fun_call?([%{id: :EXCLAMATION} | _tokens]), do: true
  def fun_call?(_tokens), do: false

  def literal?([%{id: :NUMBER} | _tokens]), do: true
  def literal?([%{id: :STRING} | _tokens]), do: true
  def literal?(_tokens), do: false

  def match([%{id: id} | _tokens], ids) when is_list(ids) do
    if id in ids, do: true, else: false
  end

  def match([%{id: id} | _tokens], id), do: true
  def match(_tokens, _id), do: false

  def next([_head | tail]), do: tail

  def get([head | rest]), do: {head, rest}

  def expect([%{id: id} | tokens], id), do: tokens
  def expect([%{id: got} | _tokens], id), do: raise("Error, expected: #{id}, got: #{got}")

  def expect_and_get([%{id: id} = token | tokens], id), do: {token, tokens}

  def expect_and_get([%{id: got} | _tokens], id), do: raise("Error, expected: #{id}, got: #{got}")

  # === Evaluation ===

  def eval([], _env), do: :ok

  def eval([head | structures], env) do
    {_result, env} = do_eval(head, env)
    eval(structures, env)
  end

  def do_eval(%{type: :fun_decl, id: id, params: params, body: body}, env) do
    env =
      add_curr_scope(
        env,
        id.value,
        %{
          body: body,
          params: Enum.map(params, fn x -> x.value end)
        }
      )

    {id.value, env}
  end

  def do_eval(%{type: :fun_call, id: id, params: params, print: print?}, env) do
    id = id.value

    {result, env} =
      cond do
        has_function?(id, env) ->
          fun = env.curr_scope[id]
          env = eval_params(params, fun.params, env)
          {result, env} = eval_list(fun.body, env)
          {List.last(result), env}

        is_built_in?(id) ->
          {result, env} = eval_fun(id, params, env)
          {result, env}
      end

    if print? do
      IO.puts(result)
      {result, env}
    else
      {result, env}
    end
  end

  def do_eval(%{id: :CHARACTER, value: value}, env) do
    if is_available?(env, value) do
      {value, env}
    else
      raise "Identifier #{value} not found"
    end
  end

  def do_eval(%{id: :NUMBER, value: value}, env) do
    {String.to_integer(value), env}
  end

  def do_eval(%{id: :IDENTIFIER, value: value}, env) do
    case Map.get(env.curr_scope, value) do
      nil ->
        raise "Identifier: #{value} not found"

      env_value ->
        {env_value, env}
    end
  end

  def do_eval(%{type: :literal, value: %{id: :NUMBER} = number}, env) do
    do_eval(number, env)
  end

  def do_eval(%{type: :literal, value: %{id: :STRING, value: value}}, env) do
    {value, env}
  end

  def do_eval(%{type: :literal, value: %{id: :IDENTIFIER} = id}, env) do
    do_eval(id, env)
  end

  def eval_list(data, env) do
    Enum.map_reduce(data, env, fn d, e ->
      {evtd, ne} = do_eval(d, e)
      {evtd, ne}
    end)
  end

  def eval_fun("+", params, env) do
    {params, env} = eval_params(params, env)
    {Enum.sum(params), env}
  end

  def eval_fun(fun, params, env) when fun in ["-", "*", "/"] do
    {[head | tail], env} = eval_params(params, env)
    {Enum.reduce(tail, head, &(&2 - &1)), env}
  end

  def eval_params(params, env) do
    eval_list(params, env)
  end

  def eval_params(params, fun_params, env) do
    {evtd, env} = eval_list(params, env)

    fun_params
    |> Enum.zip(evtd)
    |> Enum.reduce(env, fn {k, v}, env ->
      add_curr_scope(env, k, v)
    end)
  end

  def new_env() do
    %{
      curr_scope: %{}
    }
  end

  def add_curr_scope(env, key, value) do
    %{env | curr_scope: Map.put(env.curr_scope, key, value)}
  end

  def has_function?(id, env) do
    Map.has_key?(env.curr_scope, id)
  end

  def is_built_in?(id) when id in ["+", "-", "*", "/"], do: true
  def is_built_in?(_id), do: false

  def is_available?(env, id) do
    Map.has_key?(env.curr_scope, id)
  end
end
