defmodule Pings.Macro.Route do
  @moduledoc """
  A macro module to make routing in Pings.Router less verbose
  """

  @doc """
  A macro to make routing easier to reason about.
  Must have a route that evalueates to true, ie :not_found, placed last
  to prevent it overwriting other routes.

    iex> req = %Pings.Struct.HTTPRequest{method: :GET, uri: "/"}
    ...>  route req do
    ...>    [GET: "/"] -> (fn(req) -> {:ok, req.params} end).()
    ...>    :not_found -> (fn(req) -> {:not_found, req.params} end).()
    ...>  end
    {:ok, []}

    iex> req = %Pings.Struct.HTTPRequest{method: :GET, uri: "/nowhere"}
    ...>  route req do
    ...>    [GET: "/"] -> (fn(req) -> {:ok, req.params} end).()
    ...>    :not_found -> (fn(req) -> {:not_found, req.params} end).()
    ...>  end
    {:not_found, []}

    iex> req = %Pings.Struct.HTTPRequest{method: :POST, uri: "/"}
    ...>  route req do
    ...>    [GET: "/"] -> (fn(req) -> {:get, req.params} end).()
    ...>    [POST: "/"] -> (fn(req) -> {:post, req.params} end).()
    ...>    :not_found -> (fn(req) -> {:not_found, req.params} end).()
    ...>  end
    {:post, []}

    iex> req = %Pings.Struct.HTTPRequest{method: :POST, uri: "/val1"}
    ...>  route req do
    ...>    [POST: "/:key1"] -> (fn(req) -> {:post, req.params} end).()
    ...>    :not_found -> (fn(req) -> {:not_found, req.params} end).()
    ...>  end
    {:post, [key1: "val1"]}

    iex> req = %Pings.Struct.HTTPRequest{method: :DELETE, uri: "/val1/val2"}
    ...>  route req do
    ...>    [DELETE: "/:key1/:key2"] -> (fn(req) -> {:delete, req.params} end).()
    ...>    :not_found -> (fn(req) -> {:not_found, req.params} end).()
    ...>  end
    {:delete, [key1: "val1", key2: "val2"]}

  """
  defmacro route(req, do: routes) do
    guards = Enum.map(routes, fn({:->, context, [[route], action]}) ->
      condition = quote do:
        get_route_info(:matching, unquote(route), unquote(req))

      result = quote do
        params = get_route_info(:params, unquote(route), unquote(req))
        %{unquote(req) | params: params} |> unquote(action)
      end

      {:->, context, [[condition], result]}
    end)

    # fall back to nil to satisfy the compiler
    quote do
      cond do
        unquote(guards)
      end
    end
  end

  @doc """
  Returns either boolean or list, depending on the action requested
  """
  @spec get_route_info(atom, list | nil, Pings.Struct.HTTPRequest) :: list | boolean
  def get_route_info(action, route, req) do
    case action do
      :matching ->
        if is_list(route) do
          {route_method, route_uri} = Enum.at(route, 0)
          req.method == route_method and uri_matches_spec?(req.uri, route_uri)
        else
          !!route # fallback for 404
        end

      :params ->
        if is_list(route) do
          {route_method, route_uri} = Enum.at(route, 0)
          if req.method == route_method do
            get_params_from_uri(req.uri, route_uri)
          else
            []
          end
        else
          [] # fallback for 404
        end
    end
  end

  @doc ~S"""
  Checks if the request URI is appliccable to the URI spec.
  Function is public for testing purposes.

  # Examples
  
    iex> uri_matches_spec?("/devices", "/devices")
    true

    iex> uri_matches_spec?("/devices1", "/devices")
    false

    iex> uri_matches_spec?("/anything_goes", "/:argument")
    true

    iex> uri_matches_spec?(
    ...>  "/eab88fbc-10c6-11e2-b622-1231381359d0/1456282364",
    ...>  "/:device_id/:epoch_time")
    true

    iex> uri_matches_spec?(
    ...>  "/eab88fbc-10c6-11e2-b622-1231381359d0",
    ...>  "/:device_id/:epoch_time")
    false

    iex> uri_matches_spec?(
    ...>  "/eab88fbc-10c6-11e2-b622-1231381359d0/1456282364",
    ...>  "/:device_id")
    false
    
    iex> uri_matches_spec?(
    ...>  "/eab88fbc-10c6-11e2-b622-1231381359d0/1456282364",
    ...>  "/all/date")
    false

  """
  @spec uri_matches_spec?(binary, binary) :: boolean
  def uri_matches_spec?(req_uri, uri_spec) do
    get_regex_from_spec(uri_spec)
    |> Regex.match?(req_uri)
  end

  @doc ~S"""
  Gets parameters from the request URI according to the URI spec.
  Function is public for testing purposes.

  # Examples

    iex> get_params_from_uri("/devices", "/devices")
    []

    iex> get_params_from_uri("/devices1", "/devices")
    []

    iex> get_params_from_uri("/anything_goes", "/:argument")
    [argument: "anything_goes"]

    iex> get_params_from_uri(
    ...>  "/eab88fbc-10c6-11e2-b622-1231381359d0/1456282364",
    ...>  "/:device_id/:epoch_time")
    [device_id: "eab88fbc-10c6-11e2-b622-1231381359d0",
      epoch_time: "1456282364"]

    iex> get_params_from_uri(
    ...>  "/eab88fbc-10c6-11e2-b622-1231381359d0",
    ...>  "/:device_id/:epoch_time")
    []

    iex> get_params_from_uri(
    ...>  "/eab88fbc-10c6-11e2-b622-1231381359d0/1456282364",
    ...>  "/:device_id")
    []
    
    iex> get_params_from_uri(
    ...>  "/1/2/3/4/5",
    ...>  "/:a/:b/:c/:d/:e")
    [a: "1", b: "2", c: "3", d: "4", e: "5"]

  """
  @spec get_params_from_uri(binary, binary) :: list
  def get_params_from_uri(req_uri, uri_spec) do
    matches = get_regex_from_spec(uri_spec) |> Regex.run(req_uri)
    if not is_nil(matches) do
      [_ | param_vals] = matches
      param_keys = get_param_keys_from_spec(uri_spec)
      compile_params(param_keys, param_vals)
    else
      []
    end
  end

  defp get_regex_from_spec(uri_spec) do
    {:ok, regex} = 
      Regex.replace(~r/\/\:[a-zA-Z][a-zA-Z0-9_]*/,
                    uri_spec, "\/([a-zA-Z0-9_-]+)")
      |> (fn (s) -> "^" <> s <> "$" end).()  
      |> Regex.compile
    regex
  end

  defp get_param_keys_from_spec(uri_spec) do
    Regex.scan(~r/\/\:([a-zA-Z][a-zA-Z0-9_]*)/,
               uri_spec, capture: :all_but_first)
    |> List.flatten
  end

  # converts param_keys to atoms and zips the atom to the respective value
  defp compile_params(param_keys, param_vals) do
    param_keys
      |> Enum.map(&String.to_atom(&1))
      |> Enum.zip(param_vals)
  end
end
