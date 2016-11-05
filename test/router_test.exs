defmodule Pings.RouterTest do
  use ExUnit.Case, async: true
  import Pings.Router
  doctest Pings.Router

  setup do
    # A valid HTTPRequest
    %{
      req: %Pings.Struct.HTTPRequest{
        method: :GET,
        uri: "/devices"
      }
    }
  end

  test "A valid URL with a response should result 200", %{req: req} do
    res = route_and_get_response(req)
    assert res.status_code == 200
  end
  
  test "An invalid URL should result 404", %{req: req} do
    req = %{req | uri: "/nowhere_to_be_seen"}
    res = route_and_get_response(req)
    assert res.status_code == 404
  end

  test "Should crash on invalid http method", %{req: req}do
    req = %{req | method: :INVALID}
    assert_raise RuntimeError, fn ->
      route_and_get_response(req)
    end
  end
end