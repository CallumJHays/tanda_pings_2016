defmodule Pings.Util.JSONEncoder do
  require Logger
  @moduledoc """
  A simple JSON Encoder for converting erlang data structures to a
  JSON encoded string.
  """

  @doc ~S"""
  Encodes the input data structure recursively

  # Examples:
  ```

    iex> json_encode(42)
    "42"
  
    iex> json_encode(42, true)
    "\"42\""

    iex> json_encode(:test)
    "\"test\""

    iex> json_encode("test")
    "\"test\""

  ```
  Keep in mind, floats are about 400x, and 4ms slower to stringify than integers

  ```

    iex> json_encode(42.12345678)
    "42.12345678"

  ```

  Structures such as maps, lists and tuples will be recursively encoded

  ```

    iex> json_encode(%{a: 1, b: "two", c: 3})
    "{\"a\":1,\"b\":\"two\",\"c\":3}"

    iex> json_encode([5,4,3,2,1])
    "[5,4,3,2,1]"

    iex> json_encode({5,4,3,2,1})
    "[5,4,3,2,1]"

  ```

  If a keyword list has only unique keys, it will be encoded as an object

  ```

    iex> json_encode([foo: 10, bar: 20, baz: 30])
    "{\"bar\":20,\"baz\":30,\"foo\":10}"

  ```

  Note that the order that a map is encoded in is by key code points.
  If a keyword list has duplicate keys, it will be renderd as an array of arrays

  ```

    iex> json_encode([foo: 10, foo: 20, baz: 30])
    "[[\"foo\",10],[\"foo\",20],[\"baz\",30]]"

    iex> map = %{a: 1, b: 3}
    ...> arr = for {k, v} <- map do
    ...>   %{map | k => v * 2}
    ...> end
    ...> json_encode(arr)
    "[{\"a\":2,\"b\":3},{\"a\":1,\"b\":6}]"
    
  ```

  """
  @spec json_encode(any) :: binary
  # handle both regular lists and keyword lists with no key duplicates
  def json_encode(list) when is_list(list) do
    if keyword_list_and_mappable?(list) do
      json_encode(Enum.into(list, %{}))
    else
      list
      |> Enum.map_join(",", &json_encode(&1))
      |> (fn(json) -> ~s([#{json}]) end).()
    end
  end

  def json_encode(map) when is_map(map) do
    map = Map.delete(map, :__struct__) # convert it from a struct if it is one
      map
      |> Map.delete(:__struct__)
      |> Enum.map_join(",", fn({key, val}) ->
        "#{json_encode(key, true)}:#{json_encode(val)}"
      end)
      |> (fn(json) -> ~s({#{json}}) end).()
  end

  # convert tuples to lists
  def json_encode(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list |> json_encode
  end
  
  def json_encode(key, as_string \\ false)

  def json_encode(number, as_string) when is_number(number) do
    if as_string do
      ~s("#{number}")
    else
      String.Chars.to_string(number)
    end
  end

  # mostly strings and atoms at this point
  def json_encode(any, _) do
    ~s("#{any}")
  end

  defp keyword_list_and_mappable?(list) do
    # if all elements are tuples and they all have unique keys
    Enum.all?(list, fn(el) ->
      is_tuple(el) and keyword_tuple?(el)
    end) and list |> Enum.uniq_by(&elem(&1, 0)) |> length == length(list)
  end

  defp keyword_tuple?(tuple) do
    tuple_size(tuple) == 2 and (tuple |> elem(0) |> is_atom)
  end
end
