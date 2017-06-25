defmodule Ace.TCP do
  @moduledoc """
  Serve application from TCP endpoint.

  To start a TCP endpoint run `start_link/2`.
  """

  @typedoc """
  Reference to the endpoint.
  """
  @type endpoint :: pid

  @typedoc """
  Configuration options used when starting and endpoint.
  """
  @type options :: [option]

  @typedoc """
  Option values used to start an endpoint.
  """
  @type option :: {:name, GenServer.name}
                | {:acceptors, non_neg_integer}
                | {:port, :inet.port_number}

  require Logger
  use Supervisor

  # Settings for the TCP socket
  @socket_options [
    # Received packets are delivered as a binary("string").
    # Alternative option is list('char list').
    {:mode, :binary},

    # Received packets are delineated on each new line.
    {:packet, :raw},

    # Set the socket to execute in passive mode.
    # The process must explicity receive incoming data by calling `TCP.recv/2`
    {:active, false},

    # it is possible for the process to complete before the kernel has released the associated network resource, and this port cannot be bound to another process until the kernel has decided that it is done.
    # A detailed explaination is given at http://hea-www.harvard.edu/~fine/Tech/addrinuse.html
    # This setting is a security vulnerability only on multi-user machines.
    # It is NOT a vulnerability from outside the machine.
    {:reuseaddr, true}
  ]

  @doc """
  Start a new endpoint with the app behaviour.

  ## Options

    * `:port` - the port to run the server on.
      Defaults to port 8080.

    * `:name` - name to register the spawned endpoint under.
      The supported values are the same as GenServers.

    * `:acceptors` - The number of servers simultaneously waiting for a connection.
      Defaults to 50.

  """
  @spec start_link({module, term}, options) :: {:ok, endpoint}
  def start_link(app = {mod, _}, options) do
    case Ace.Application.is_implemented?(mod) do
      true ->
        :ok
      false ->
        Logger.warn("#{__MODULE__}: #{mod} does not implement Ace.Application behaviour.")
    end
    name = Keyword.get(options, :name)
    Supervisor.start_link(__MODULE__, {app, options}, [name: name])
  end

  @doc """
  Retrieve the port number for an endpoint.
  """
  @spec port(endpoint) :: {:ok, :inet.port_number}
  def port(endpoint) do
    GenServer.call(endpoint, :port)
  end

  ## Server Callbacks

  def init({app, options}) do
    port = Keyword.get(options, :port, 8080)

    # A better name might be acceptors_count, but is rather verbose.
    acceptors = Keyword.get(options, :acceptors, 50)

    # Setup a socket to listen with our TCP options
    {:ok, raw_listen_socket} = :gen_tcp.listen(port, @socket_options)
    listen_socket = {:tcp, raw_listen_socket}

    # {:ok, server_supervisor} = Ace.Server.Supervisor.start_link(app)
    # {:ok, governor_supervisor} = Ace.Governor.Supervisor.start_link(server_supervisor, listen_socket, acceptors)

    # Fetch and display the port information for the listening listen_socket.
    {:ok, port} = Ace.Connection.port(listen_socket)
    name = Keyword.get(options, :name, __MODULE__)
    :ok = Logger.debug("#{name} listening on port: #{port}")

    children = [
      supervisor(Ace.Server.Supervisor, [app]),
      supervisor(Ace.Governor.Supervisor, [:bob, listen_socket, acceptors]),
    ]

    supervise(children, strategy: :rest_for_one)
    # |> IO.inspect
    # # {:ok, {listen_socket, server_supervisor, governor_supervisor}}
  end

  def handle_call(:port, _from, state = {socket, _, _}) do
    port = Ace.Connection.port(socket)
    {:reply, port, state}
  end
end
