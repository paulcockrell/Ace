defmodule MyServerTest do
  use ExUnit.Case
  require Ace.Server
  @host {127, 0, 0, 1}

  setup do
    {:ok, server} = MyServer.start_link(self())
    {:ok, socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(socket)
    {:ok, ref} = Ace.Server.accept_connection(server, {:tcp, socket})
    {:ok, port: port, ref: ref}
  end

  test "quick 200 response", %{port: port} do
    {:ok, connection} = open_connection(port)
    start_line = "GET / HTTP/1.1\r\n"
    :ok = :gen_tcp.send(connection, start_line)
    assert_receive 5, 10_000
  end

  test "quick 404 response", %{port: port} do
    {:ok, connection} = open_connection(port)
    start_line = "GET /random HTTP/1.1\r\n"
    :ok = :gen_tcp.send(connection, start_line)
    assert_receive 5, 10_000
  end

  def open_connection(port) do
    :gen_tcp.connect(@host, port, [:binary])
    # Could assert ref received
  end
end
