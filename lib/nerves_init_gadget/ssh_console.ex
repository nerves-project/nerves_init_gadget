defmodule Nerves.InitGadget.SSHConsole do
  @moduledoc """
  SSH IEx console.
  """
  use GenServer

  @doc """
  Since ctrl-c is intercepted in default Nerves config,
  We need to be able to exit the shell somehow.
  """
  def shell_exit, do: GenServer.call(__MODULE__, :ssh_exit)

  @doc false
  def start_link(%{ssh_console_port: nil}), do: :ignore

  def start_link(opts) do
    GenServer.start_link(__MODULE__, [opts], name: __MODULE__)
  end

  def init([opts]) do
    ssh = start_ssh(opts)
    {:ok, %{ssh: ssh, opts: opts}}
  end

  def terminate(_, %{ssh: ssh}) do
    :ssh.stop_daemon(ssh)
  end

  def handle_call(:ssh_exit, from, %{ssh: ssh} = state) do
    # Reply to avoid crashing the call.
    GenServer.reply(from, :ok)
    :ok = :ssh.stop_daemon(ssh)
    # Sleep here so when we restart, the port is open.
    Process.sleep(5000)
    new_ssh = start_ssh(state.opts)
    {:noreply, :ok, %{state | ssh: new_ssh}}
  end

  defp start_ssh(%{ssh_console_port: port}) do
    authorized_keys =
      Application.get_env(:nerves_firmware_ssh, :authorized_keys, [])
      |> Enum.join("\n")

    decoded_authorized_keys = :public_key.ssh_decode(authorized_keys, :auth_keys)

    cb_opts = [authorized_keys: decoded_authorized_keys]

    {:ok, ssh} =
      :ssh.daemon(port, [
        {:id_string, :random},
        {:key_cb, {Nerves.Firmware.SSH.Keys, cb_opts}},
        {:system_dir, Nerves.Firmware.SSH.Application.system_dir()},
        {:shell, {Elixir.IEx, :start, []}}
      ])

    ssh
  end
end
