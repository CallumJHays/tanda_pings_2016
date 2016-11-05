use Mix.Config

config(:pings, [
  database_conn: %{
    host: 'tanda-pings.clv9sdynpfwp.ap-southeast-2.rds.amazonaws.com',
    port: 5432,
    dbname: "pings",
    username: "username",
    password: "password"
  }
])
