# TccDepeeringElixir

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Installing Elixir
https://www.erlang.org/downloads.html
https://elixir-lang.org/install/

Dont forget to install bgpdump

## Running shortcuts 

You can run: ./reset.sh 
To run all the commands necessary to run this locally.
To start the server:
mix phx.server
You might have some issues where it doesn't actually stop running on the port. When that happens, you can make it stop running with:
fuser -k 4000/tcp

tip for running postgres (had to do it this way):
sudo -u postgres /usr/local/pgsql/bin/pg_ctl start -D /usr/local/pgsql/data -l /usr/local/pgsql/data/server.log 

tip for closing postgres:
sudo -u postgres /usr/local/pgsql/bin/pg_ctl stop -D /usr/local/pgsql/data -m fast
 
