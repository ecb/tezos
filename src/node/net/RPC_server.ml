(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2016.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

open RPC
open Logging.RPC

(* public types *)
type server = (* hidden *)
  { shutdown : unit -> unit Lwt.t ;
    mutable root : unit directory }

module ConnectionMap = Map.Make(Cohttp.Connection)

exception Invalid_method
exception Options_preflight
exception Cannot_parse_body of string

let check_origin_matches origin allowed_origin =
  String.equal "*" allowed_origin ||
  String.equal allowed_origin origin ||
  begin
    let allowed_w_slash = allowed_origin ^ "/" in
    let len_a_w_s = String.length allowed_w_slash in
    let len_o = String.length origin in
    (len_o >= len_a_w_s) &&
    String.equal allowed_w_slash @@ String.sub origin 0 len_a_w_s
  end

let find_matching_origin allowed_origins origin =
  let matching_origins = List.filter (check_origin_matches origin) allowed_origins in
  let compare_by_length_neg a b = ~- (compare (String.length a) (String.length b)) in
  let matching_origins_sorted = List.sort compare_by_length_neg matching_origins in
  match matching_origins_sorted with
  | [] -> None
  | x :: _ -> Some x

let make_cors_headers ?(headers=Cohttp.Header.init ())
    cors_allowed_headers cors_allowed_origins origin_header =
  let cors_headers = Cohttp.Header.add_multi headers
      "Access-Control-Allow-Headers" cors_allowed_headers in
  match origin_header with
  | None -> cors_headers
  | Some origin ->
      match find_matching_origin cors_allowed_origins origin with
      | None -> cors_headers
      | Some allowed_origin ->
          Cohttp.Header.add_multi cors_headers
            "Access-Control-Allow-Origin" [allowed_origin]

(* Promise a running RPC server. *)
let launch ?pre_hook ?post_hook ?(host="::") mode root cors_allowed_origins cors_allowed_headers =
  (* launch the worker *)
  let cancelation, canceler, _ = Lwt_utils.canceler () in
  let open Cohttp_lwt_unix in
  let streams = ref ConnectionMap.empty in
  let create_stream _io con to_string (s: _ Answer.stream) =
    let running = ref true in
    let stream =
      Lwt_stream.from
        (fun () ->
           if not !running then Lwt.return None else
             s.next () >|= function
             | None -> None
             | Some x -> Some (to_string x)) in
    let shutdown () = running := false ; s.shutdown () in
    streams := ConnectionMap.add con shutdown !streams ;
    stream
  in
  let shutdown_stream con =
    try ConnectionMap.find con !streams ()
    with Not_found -> () in
  let call_hook (io, con) req ?(answer_404 = false) hook =
    match hook with
    | None -> Lwt.return None
    | Some hook ->
        Lwt.catch
          (fun () ->
             hook (Uri.path (Cohttp.Request.uri req))
             >>= fun { Answer.code ; body } ->
             if code = 404 && not answer_404 then
               Lwt.return None
             else
               let body = match body with
                 | Answer.Empty ->
                     Cohttp_lwt_body.empty
                 | Single body ->
                     Cohttp_lwt_body.of_string body
                 | Stream s ->
                     let stream =
                       create_stream io con (fun s -> s) s in
                     Cohttp_lwt_body.of_stream stream in
               Lwt.return_some
                 (Response.make ~flush:true ~status:(`Code code) (),
                  body))
          (function
            | Not_found -> Lwt.return None
            | exn -> Lwt.fail exn) in
  let callback (io, con) req body =
    (* FIXME: check inbound adress *)
    let path = Utils.split_path (Uri.path (Cohttp.Request.uri req)) in
    let req_headers = Cohttp.Request.headers req in
    let origin_header = Cohttp.Header.get req_headers "origin" in
    lwt_log_info "(%s) receive request to %s"
      (Cohttp.Connection.to_string con) (Uri.path (Cohttp.Request.uri req)) >>= fun () ->
    Lwt.catch
      (fun () ->
         call_hook (io, con) req pre_hook >>= function
         | Some res ->
             Lwt.return res
         | None ->
             lookup root () path >>= fun handler ->
             begin
               match req.meth with
               | `POST -> begin
                   Cohttp_lwt_body.to_string body >>= fun body ->
                   match Data_encoding_ezjsonm.from_string body with
                   | Error msg -> Lwt.fail (Cannot_parse_body msg)
                   | Ok body -> Lwt.return (Some body)
                 end
               | `GET -> Lwt.return None
               | `OPTIONS -> Lwt.fail Options_preflight
               | _ -> Lwt.fail Invalid_method
             end >>= fun body ->
             handler body >>= fun { Answer.code ; body } ->
             let body = match body with
               | Empty ->
                   Cohttp_lwt_body.empty
               | Single json ->
                   Cohttp_lwt_body.of_string (Data_encoding_ezjsonm.to_string json)
               | Stream s ->
                   let stream =
                     create_stream io con Data_encoding_ezjsonm.to_string s in
                   Cohttp_lwt_body.of_stream stream in
             lwt_log_info "(%s) RPC %s"
               (Cohttp.Connection.to_string con)
               (if Cohttp.Code.is_error code
                then "failed"
                else "success") >>= fun () ->
             let headers = make_cors_headers cors_allowed_headers cors_allowed_origins origin_header in
             Lwt.return (Response.make
                           ~flush:true ~status:(`Code code) ~headers (), body))
      (function
        | Not_found | Cannot_parse _ ->
            lwt_log_info "(%s) not found"
              (Cohttp.Connection.to_string con) >>= fun () ->
            (call_hook (io, con) req ~answer_404: true post_hook >>= function
              | Some res -> Lwt.return res
              | None ->
                  Lwt.return (Response.make ~flush:true ~status:`Not_found (),
                              Cohttp_lwt_body.empty))
        | Invalid_method ->
            lwt_log_info "(%s) bad method"
              (Cohttp.Connection.to_string con) >>= fun () ->
            let headers =
              Cohttp.Header.add_multi (Cohttp.Header.init ())
                "Allow" ["POST"] in
            let headers = make_cors_headers ~headers cors_allowed_headers cors_allowed_origins origin_header in
            Lwt.return (Response.make
                          ~flush:true ~status:`Method_not_allowed
                          ~headers (),
                        Cohttp_lwt_body.empty)
        | Cannot_parse_body msg ->
            lwt_log_info "(%s) can't parse RPC body"
              (Cohttp.Connection.to_string con) >>= fun () ->
            Lwt.return (Response.make ~flush:true ~status:`Bad_request (),
                        Cohttp_lwt_body.of_string msg)
        | Options_preflight ->
            lwt_log_info "(%s) RPC preflight"
              (Cohttp.Connection.to_string con) >>= fun () ->
            let headers = make_cors_headers cors_allowed_headers cors_allowed_origins origin_header in
            Lwt.return (Response.make ~flush:true ~status:(`Code 200) ~headers (),
                        Cohttp_lwt_body.empty)
        | e -> Lwt.fail e)
  and conn_closed (_, con) =
    log_info "connection close %s" (Cohttp.Connection.to_string con) ;
    shutdown_stream con  in
  Conduit_lwt_unix.init ~src:host () >>= fun ctx ->
  let ctx = Cohttp_lwt_unix_net.init ~ctx () in
  let stop = cancelation () in
  let _server =
    Server.create
      ~stop ~ctx ~mode
      (Server.make ~callback ~conn_closed ()) in
  let shutdown () =
    canceler () >>= fun () ->
    lwt_log_info "server not really stopped (cohttp bug)" >>= fun () ->
    Lwt.return () (* server *) (* FIXME: bug in cohttp *) in
  Lwt.return { shutdown ; root }

let root_service { root } = root

let set_root_service server root = server.root <- root

let shutdown server =
  server.shutdown ()
