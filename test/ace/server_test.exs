defmodule Ace.ServerTest do
  use ExUnit.Case

  defmodule TestApplication do
    use Ace.Application

    def handle_connect(info, test) do
      send(test, info)
      {:nosend, test}
    end

    def handle_packet(_packet, state) do
      {:nosend, state}
    end

    def handle_info(_info, state) do
      {:nosend, state}
    end

    def handle_disconnect(_info, _test) do
      :ok
    end
  end

  defmodule EchoServer do
    use Ace.Application
    def handle_connect(_, state) do
      {:nosend, state}
    end

    def handle_packet(inbound, state) do
      {:send, "ECHO: #{String.strip(inbound)}\n", state}
    end

    def handle_info(_info, state) do
      {:nosend, state}
    end

    def handle_disconnect(_info, _test) do
      :ok
    end
  end

  require Ace.Server
  @host {127, 0, 0, 1}

  setup config do
    config = Map.put(config, :pid, self())
    {:ok, server} = Ace.Server.start_link({__MODULE__, config})
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})
    {:ok, port: port, ref: ref}
  end

  def handle_connect(
    info,
    %{test: :"test tcp connection information", pid: pid})
  do
    send(pid, info)
    {:nosend, nil}
  end

  test "tcp connection information",
    %{port: port, ref: ref}
  do
    {:ok, client} = connect_to(port)
    {:ok, client_name} = :inet.sockname(client)
    assert_receive Ace.Server.connection_ack(^ref, conn = %{peer: ^client_name, transport: :tcp})
    assert_receive ^conn
  end

  def handle_connect(
    _info,
    %{test: :"test writing data on connect", pid: pid})
  do
    {:send, "WELCOME", :no_state}
  end

  test "writing data on connect", %{port: port} do
    {:ok, client} = connect_to(port)
    assert {:ok, "WELCOME"} = :gen_tcp.recv(client, 0, 2000)
  end

  def connect_to(port) do
    :gen_tcp.connect(@host, port, [{:active, false}, :binary])
  end


  test "server is initialised with tls connection information" do
    cert_path = Path.expand("./tls/cert.pem", __ENV__.file |> Path.dirname)
    key_path = Path.expand("./tls/key.pem", __ENV__.file |> Path.dirname)
    {:ok, server} = Ace.Server.start_link({TestApplication, self()})
    {:ok, listen_socket} = :ssl.listen(0,
      mode: :binary,
      packet: :line,
      active: false,
      reuseaddr: true,
      certfile: cert_path,
      keyfile: key_path)
    {:ok, {_, port}} = :ssl.sockname(listen_socket)
    {:ok, ref} = Ace.Server.accept_connection(server, {:tls, listen_socket})
    {:ok, client} = :ssl.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    {:ok, client_name} = :ssl.sockname(client)
    assert_receive Ace.Server.connection_ack(^ref, conn = %{peer: ^client_name, transport: :tls})
    assert_receive ^conn
  end

  test "echos each message" do
    {:ok, server} = Ace.Server.start_link({EchoServer, []})
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, _ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client, "blob\n")
    assert {:ok, "ECHO: blob\n"} = :gen_tcp.recv(client, 0)
  end

  test "error when recieves message before connection" do
    Process.flag(:trap_exit, true)
    {:ok, server} = Ace.Server.start_link({BroadcastServer, []})

    send(server, :message)
    assert_receive {:EXIT, ^server, details}, 10_000
    assert {%RuntimeError{}, _stacktrace} = details
  end

  test "socket broadcasts server notification" do
    {:ok, server} = Ace.Server.start_link({BroadcastServer, self()})
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, _ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    receive do
      {:register, pid} ->
        send(pid, {:notify, "HELLO"})
      end
    assert {:ok, "HELLO\r\n"} = :gen_tcp.recv(client, 0)
  end

  test "socket ignores debug messages" do
    {:ok, server} = Ace.Server.start_link({BroadcastServer, self()})
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, _ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    receive do
      {:register, pid} ->
        send(pid, :debug)
    end
    assert {:error, :timeout} == :gen_tcp.recv(client, 0, 1000)
  end

  test "state is passed through messages" do
    {:ok, server} = Ace.Server.start_link({CounterServer, 0})
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, _ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    :ok = :gen_tcp.send(client, "INC\r\n")
    # If sending raw packets they can be read as part of the same packet if sent too fast.
    :timer.sleep(100)
    :ok = :gen_tcp.send(client, "INC\r\n")
    :timer.sleep(100)
    :ok = :gen_tcp.send(client, "TOTAL\r\n")
    assert {:ok, "2\r\n"} = :gen_tcp.recv(client, 0, 2000)
  end

  test "can set a timeout in response to new connection" do
    {:ok, server} = Ace.Server.start_link({Timeout, 10})
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, _ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])

    assert {:ok, "HI\r\n"} = :gen_tcp.recv(client, 0)
    assert {:ok, "TIMEOUT 10\r\n"} = :gen_tcp.recv(client, 0, 1000)
  end

  test "can set a timeout in response to a packet" do
    {:ok, server} = Ace.Server.start_link({Timeout, 10})
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, _ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])

    {:ok, "HI\r\n"} = :gen_tcp.recv(client, 0, 1000)
    {:ok, "TIMEOUT 10\r\n"} = :gen_tcp.recv(client, 0, 1000)

    :ok = :gen_tcp.send(client, "PING\r\n")
    {:ok, "PONG\r\n"} = :gen_tcp.recv(client, 0, 1000)
    {:ok, "TIMEOUT 10\r\n"} = :gen_tcp.recv(client, 0, 1000)
  end

  test "can set a timeout in response to a packet with no immediate reply" do
    {:ok, server} = Ace.Server.start_link({Timeout, 10})
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, _ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])

    {:ok, "HI\r\n"} = :gen_tcp.recv(client, 0, 1000)
    {:ok, "TIMEOUT 10\r\n"} = :gen_tcp.recv(client, 0, 1000)

    :ok = :gen_tcp.send(client, "OTHER\r\n")
    {:ok, "TIMEOUT 10\r\n"} = :gen_tcp.recv(client, 0, 1000)
  end

  test "can respond by closing the connection" do
    {:ok, server} = Ace.Server.start_link({CloseIt, self()})
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, _ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})

    {:ok, port} = :inet.port(listen_socket)
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])

    assert true == Process.alive?(server)
    send(server, :close)

    assert {:error, :closed} = :gen_tcp.recv(client, 0, 1000)
    :timer.sleep(1000)
    assert false == Process.alive?(server)
  end

  test "server exits when connection closes" do
    {:ok, server} = Ace.Server.start_link({TestApplication, self()})
    {:ok, listen_socket} = :gen_tcp.listen(0, mode: :binary, packet: :line, active: false, reuseaddr: true)
    {:ok, port} = :inet.port(listen_socket)
    {:ok, ref} = Ace.Server.accept_connection(server, {:tcp, listen_socket})
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [{:active, false}, :binary])
    assert_receive Ace.Server.connection_ack(^ref, conn)
    assert_receive ^conn
    :timer.sleep(50)
    :ok = :gen_tcp.close(client)
    :timer.sleep(50)
    assert false == Process.alive?(server)
  end
end
