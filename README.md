# Pings

A pure Elixir + OTP solution to the Tanda Challenge for summer 2016.

You can check it hosted on a live server [HERE](http://54.206.64.114:3000)

## Installation

### Elixir + OTP
Elixir, BEAM and OTP needs to be installed for this application to run.
Elixir, OTP and tools such as mix can be installed with the following
commands in Ubuntu.
```
wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb &&
sudo dpkg -i erlang-solutions_1.0_all.deb && 
rm erlang-solutions_1.0_all.deb &&
sudo apt-get update;
sudo apt-get install esl-erlang elixir;
```
Installation instructions for operating systems can be found
[on the Elixir-Lang website](http://elixir-lang.org/install.html)

### Database configuration
This application is solely configured to run on Postgres 9.5.
It might work for other versions of Postgres, but it has only been tested on 
an instance of Postgres 9.5 running on Amazon RD. Database config details
must be included in `config/config.exs`. Below is an example config file.
```
use Mix.Config

config(:pings, [
  database_conn: %{
    host: 'database.hash.region.rds.amazonaws.com',
    port: 5432,
    dbname: "db-name",
    username: "username",
    password: "password"
  }
])
```
The database user must be able to read, update and delete records from
the "pings" table on the database. The "pings" table must be created in
the Postgres CLI "`psql`" before starting the application using this command:
```
CREATE TABLE pings (device_id varchar(40) NOT NULL, epoch_time bigint NOT NULL);
```

## Running the application
The application can be compiled and run with the following command
in the application root directory:
```
mix run --no-halt
```

## TODOS
1. SSL/TLS DB encryption
2. Distribution across nodes (for lulz)