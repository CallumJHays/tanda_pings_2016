defmodule PingsTest do
  use ExUnit.Case

  setup do
    Application.stop(:pings)
    :ok = Application.start(:pings)
  end

  setup do
    opts = [:binary, packet: :line, active: false]
    {:ok, socket} = :gen_tcp.connect('localhost', 3000, opts)
    {:ok, socket: socket}
  end

  test "accepts requests on port 3000", %{socket: socket} do
    assert is_port(socket)
  end

  # defp send_and_recv(socket, req) do
  #   :ok = :gen_tcp.send(socket, req)
  #   {:ok, resp} = :gen_tcp.recv(socket, 0, 1000)
  #   resp
  # end
end
