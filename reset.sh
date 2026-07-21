
sudo -u postgres /usr/local/pgsql/bin/pg_ctl stop -D /usr/local/pgsql/data -m fast
sudo -u postgres /usr/local/pgsql/bin/pg_ctl start -D /usr/local/pgsql/data -l /usr/local/pgsql/data/server.log 
fuser -k 4000/tcp
echo "Starting server on port 4000..."

mix phx.server
