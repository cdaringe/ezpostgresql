let conninfo = "host=localhost"

let raw_execute query =
  let conn = new Postgresql.connection ~conninfo () in
  let _ = conn#exec ~expect:[Postgresql.Command_ok] query in
  conn#finish

let create_test_table () =
  raw_execute "
    CREATE TABLE IF NOT EXISTS person (
      name VARCHAR(100) NOT NULL,
      age INTEGER NOT NULL
    )
  "

let drop_test_table () =
  raw_execute "
    DROP TABLE IF EXISTS person
  "

let tear_down ?conn () =
  raw_execute "
    TRUNCATE TABLE person
  ";
  match conn with
  | None -> ()
  | Some c -> c#finish

let tests = [

  "connect", [
    Alcotest_lwt.test_case "could connect" `Quick (fun _ _ ->
        let%lwt conn = Ezpostgresql.connect ~conninfo () in
        let host = conn#host in
        let%lwt () = Ezpostgresql.finish conn in
        Lwt.return @@ Alcotest.(check (string)) "same string" "localhost" host
      )
  ];

  "one", [
    Alcotest_lwt.test_case "could run `one` query" `Quick (fun _ _ ->
        let%lwt conn = Ezpostgresql.connect ~conninfo () in
        let () = raw_execute "
          INSERT INTO person VALUES ('Bobby', 19), ('Anne', 18)
        " in

        let%lwt res =
          Ezpostgresql.one ~query:"
            SELECT * FROM person WHERE name = $1
          " ~params:[| "Bobby" |] conn in

        let () = tear_down ~conn () in
        Lwt.return @@ Alcotest.(check (string)) "same string" "Bobby" (res.(0))
      )
  ];

  "all", [
    Alcotest_lwt.test_case "could run `all` query" `Quick (fun _ _ ->
        let%lwt conn = Ezpostgresql.connect ~conninfo () in
        let () = raw_execute "
          INSERT INTO person VALUES ('Bobby', 19), ('Anne', 18)
        " in

        let%lwt res = Ezpostgresql.all ~query:"
          SELECT * FROM person
        " conn in

        let () = tear_down ~conn () in
        Lwt.return @@ Alcotest.(check (int)) "same int" 2 (Array.length res)
      )
  ];

  "command", [
    Alcotest_lwt.test_case "could run `command` query" `Quick (fun _ _ ->
        let%lwt conn = Ezpostgresql.connect ~conninfo () in
        let%lwt () = Ezpostgresql.command "
          CREATE TEMP TABLE test_data (some_num INTEGER NOT NULL)
        " conn in
        let%lwt () = Ezpostgresql.command "
          INSERT INTO test_data VALUES (2)
        " conn in
        let%lwt res = Ezpostgresql.one "
          SELECT some_num FROM test_data
        " conn in
        let () = tear_down ~conn () in
        Lwt.return @@ Alcotest.(check (int)) "same int" 2 (int_of_string res.(0))
      )
  ];

  "Pool.create", [
    Alcotest_lwt.test_case "could use connection from pool" `Quick (fun _ _ ->
        let pool = Ezpostgresql.Pool.create ~conninfo ~size:10 () in
        Lwt_pool.use pool (fun c ->
            Lwt.return @@ Alcotest.(check (string)) "same string" "localhost" c#host
          )
      )
  ];

  "Pool.one", [
    Alcotest_lwt.test_case "could run `one` query using pool" `Quick (fun _ _ ->
        let pool = Ezpostgresql.Pool.create ~conninfo ~size:10 () in
        let () = raw_execute "
          INSERT INTO person VALUES ('Bobby', 19), ('Anne', 18)
        " in

        let%lwt res = Ezpostgresql.Pool.one ~query:"
          SELECT * FROM person WHERE name = $1
        " ~params:[| "Bobby" |] pool in

        let () = tear_down () in
        Lwt.return @@ Alcotest.(check (string)) "same string" "Bobby" (res.(0))
      )
  ];

  "Pool.all", [
    Alcotest_lwt.test_case "could run `all` query using pool" `Quick (fun _ _ ->
        let pool = Ezpostgresql.Pool.create ~conninfo ~size:10 () in
        let () = raw_execute "
          INSERT INTO person VALUES ('Bobby', 19), ('Anne', 18)
        " in

        let%lwt res = Ezpostgresql.Pool.all ~query:"
          SELECT * FROM person
        " pool in

        let () = tear_down () in
        Lwt.return @@ Alcotest.(check (int)) "same int" 2 (Array.length res)
      )
  ];

  "Pool.command", [
    Alcotest_lwt.test_case "could run `command` query" `Quick (fun _ _ ->
        let pool = Ezpostgresql.Pool.create ~conninfo ~size:10 () in
        let%lwt () = Ezpostgresql.Pool.command "
          CREATE TEMP TABLE test_data (some_num INTEGER NOT NULL)
        " pool in
        let%lwt () = Ezpostgresql.Pool.command "
          INSERT INTO test_data VALUES (2)
        " pool in
        let%lwt res = Ezpostgresql.Pool.one "
          SELECT some_num FROM test_data
        " pool in
        Lwt.return @@ Alcotest.(check (int)) "same int" 2 (int_of_string res.(0))
      )
  ];

  "Transaction", [
    Alcotest_lwt.test_case "could run `command` in transaction" `Quick (fun _ _ ->
        let%lwt conn = Ezpostgresql.connect ~conninfo () in

        let%lwt () = Ezpostgresql.Transaction.begin_ (fun trx ->
            let%lwt () = Ezpostgresql.Transaction.command ~query:"
              INSERT INTO person VALUES ('Bobby', 19)
            " trx in
            let%lwt () = Ezpostgresql.Transaction.command ~query:"
              INSERT INTO person VALUES ('Anne', 18)
            " trx in
            Ezpostgresql.Transaction.commit trx
          ) conn in

        let%lwt res = Ezpostgresql.all "
          SELECT * FROM person
        " conn in

        let () = tear_down ~conn () in
        Lwt.return @@ Alcotest.(check (int)) "same int" 2 (Array.length res)
      );

    Alcotest_lwt.test_case "rollback aborts all commands" `Quick (fun _ _ ->
        let%lwt conn = Ezpostgresql.connect ~conninfo () in

        let%lwt () = Ezpostgresql.Transaction.begin_ (fun trx ->
            let%lwt () = Ezpostgresql.Transaction.command ~query:"
              INSERT INTO person VALUES ('Bobby', 19)
            " trx in
            let%lwt () = Ezpostgresql.Transaction.command ~query:"
              INSERT INTO person VALUES ('Anne', 18)
            " trx in
            Ezpostgresql.Transaction.rollback trx
          ) conn in

        let%lwt res = Ezpostgresql.all "
          SELECT * FROM person
        " conn in

        let () = tear_down ~conn () in
        Lwt.return @@ Alcotest.(check (int)) "same int" 0 (Array.length res)
      )
  ];

  "Transaction.Pool", [
    Alcotest_lwt.test_case "could run `command` in transaction using pool" `Quick (fun _ _ ->
        let pool = Ezpostgresql.Pool.create ~conninfo ~size:10 () in

        let%lwt () = Ezpostgresql.Transaction.Pool.begin_ (fun trx ->
            let%lwt () = Ezpostgresql.Transaction.command ~query:"
              INSERT INTO person VALUES ('Bobby', 19)
            " trx in
            let%lwt () = Ezpostgresql.Transaction.command ~query:"
              INSERT INTO person VALUES ('Anne', 18)
            " trx in
            Ezpostgresql.Transaction.commit trx
          ) pool in

        let%lwt res = Ezpostgresql.Pool.all "
          SELECT * FROM person
        " pool in

        let () = tear_down () in
        Lwt.return @@ Alcotest.(check (int)) "same int" 2 (Array.length res)
      );

    Alcotest_lwt.test_case "rollback aborts all commands" `Quick (fun _ _ ->
        let pool = Ezpostgresql.Pool.create ~conninfo ~size:10 () in

        let%lwt () = Ezpostgresql.Transaction.Pool.begin_ (fun trx ->
            let%lwt () = Ezpostgresql.Transaction.command ~query:"
              INSERT INTO person VALUES ('Bobby', 19)
            " trx in
            let%lwt () = Ezpostgresql.Transaction.command ~query:"
              INSERT INTO person VALUES ('Anne', 18)
            " trx in
            Ezpostgresql.Transaction.rollback trx
          ) pool in

        let%lwt res = Ezpostgresql.Pool.all "
          SELECT * FROM person
        " pool in

        let () = tear_down () in
        Lwt.return @@ Alcotest.(check (int)) "same int" 0 (Array.length res)
      )

  ];

]

let _ =
  drop_test_table ();
  create_test_table ();
  Alcotest.run "Ezpostgresql" tests
