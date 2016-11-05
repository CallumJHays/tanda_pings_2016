defmodule Pings.Struct.HTTPRequest do
  @moduledoc """
  Module struct representing a simplified HTTP request object that is passed
  around the application
  """
  defstruct([
    method: nil,
    uri: nil,
    headers: [],
    params: [],
    query: []
  ])
end