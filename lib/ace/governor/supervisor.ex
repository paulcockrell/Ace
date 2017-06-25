defmodule Ace.Governor.Supervisor do
  @moduledoc """
  Supervise governors to maintain a pool of accepting servers.
  """
  use Supervisor

  @doc """
  Starts a supervised pool of governor processes.
  """
  @spec start_link(pid, Ace.Connection.connection, non_neg_integer) :: {:ok, pid}
  def start_link(server_supervisor, listen_socket, acceptors) do
    {:ok, server_supervisor} = Process.get() |> Keyword.fetch(Ace.Server.Supervisor)
    {:ok, supervisor} = Supervisor.start_link(__MODULE__, {server_supervisor, listen_socket}, [])
    # To speed up a server multiple process can be listening for a connection simultaneously.
    # In this case n Governors will start n Servers listening before a single connection is received.
    for _index <- 1..acceptors do
      Supervisor.start_child(supervisor, [])
    end
    {:ok, supervisor}
  end

  def drain(supervisor) do
    Supervisor.which_children(supervisor)
    |> Enum.map(fn({_i, pid, :worker, _}) ->
      ref = Process.monitor(pid)
      true = Process.exit(pid, :shutdown)
      ref
    end)
    |> Enum.map(fn(ref) ->
      receive do
        {:DOWN, ^ref, :process, _pid, _reason} ->
          :ok
      end
    end)
    :ok
  end

  ## SERVER CALLBACKS

  def init({server_supervisor, listen_socket}) do
    children = [
      worker(Ace.Governor, [listen_socket, server_supervisor], restart: :transient)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end
end
