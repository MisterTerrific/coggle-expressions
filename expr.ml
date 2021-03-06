open Core.Std
open Async.Std
(* open Cohttp_async *)
open Async_ssl.Std
open Sexplib.Std
(* open Yojson *)
(* open Cohttp_lwt_unix *)
(* open Str *)


(* let response_handler code = *)
(*   let token_url = "https://coggle.it/token?code=" ^ code ^  *)

(* let get_secret = *)
(*   let contents = Reader.file_contents "../moonlandings.txt" *)
(*       in let d = contents in d in  *)
(*               match (contents |> fun _ -> Deferred.peek contents) with *)
(*               | None -> "" *)
(*               | Some x ->  x *)

exception Diagram_not_found
exception Code_not_found
exception Deferred_is_None

let tkn = ref ""
let inet_addr = ref None

let replace old _new str  =
  Str.global_replace (Str.regexp old) _new str

let tokenize code =
  replace "(" " ( " code
  |> replace ")" " ) "
  (* |> fun y -> String.slice y 1 (String.length y - 1) *)
  |> fun x -> String.split x ~on: ' '
              |> fun l -> List.filter l (fun s -> s <> "")





(* let insert_replaced_data begin_index close_index original_str sub_str = *)
(*   match (begin_index > 0) with *)
(*   | true -> *)
(*     let before = Str.string_before original_str begin_index in *)
(*     if close_index < (String.length original_str - 1) then *)
(*       let after = Str.string_after original_str close_index in *)
(*       String.concat [before; sub_str; after] *)
(*     else (\* reach the last index e.g. the end of the string *\) *)
(*       String.concat [before; sub_str] *)
(*   | false -> (\* starts at the very first index so nothing before it*\) *)
(*     if close_index < (String.length original_str - 1) then *)
(*       let after = Str.string_after original_str close_index in *)
(*       String.concat [sub_str; after] *)
(*     else *)
(*       sub_str *)

(* let rec replace_spaces index data = *)
(*   try *)
(*     let opening_quote = Str.search_forward (Str.regexp "\\\"") data index in *)
(*     let closing_quote = Str.search_forward (Str.regexp "\\\"") data (opening_quote + 1) in *)
(*     String.sub ~pos:opening_quote ~len:(closing_quote - 1) data *)
(*     |> replace " " "§" *)
(*     |> insert_replaced_data opening_quote closing_quote data *)
(*     |> replace_spaces (closing_quote + 1) (\* the last param is always added from the pipe*\) *)
(*    with *)
(*      Not_found -> data *)

(* let replace_spaces opening_quote closing_quote data f = *)
(*     String.sub ~pos:opening_quote ~len:(closing_quote - 1) data *)
(*     |> replace " " "§" *)
(*     |> insert_replaced_data opening_quote closing_quote data *)
(*     |> f (closing_quote + 1) (\* the last param is always added from the pipe*\) *)
(*    (\* with *\) *)
(*    (\*   Not_found -> data *\) *)

(* let rec find_quotes index data = *)
(*   try *)
(*     match (String.index_from data index '"') with *)
(*     | None -> data *)
(*     | Some x -> *)
(*       (match (String.index_from data (x + 1) '"') with *)
(*       | None -> data *)
(*       | Some y -> replace_spaces x y data find_quotes) *)
(*   with *)
(*   (\* | Invalid_argument s -> data *\) *)
(*   | Not_found -> data *)

let data_from_file = ref ""

(* Concatenates the rest of the data
   if there is no matching double quote found *)
let concat_remaining last_index len replaced_data =
  match (last_index < (len - 1)) with
  | false -> replaced_data
(* Nothing to concat as there is nothing after the last index*)
  | true when last_index = 0 -> replaced_data
  | true -> (* replaced_data ^ (Str.string_after !data_from_file last_index) *)
    String.concat [replaced_data; (Str.string_after !data_from_file last_index)]
(* "§" *)


(* Tranverses data for strings *)
(* and replaces spaces in string with unique character *)
(* Does this by finding matching double quotes "" *)
(* then replaces the spaces between them *)
(* Also concatenates to previously traversed strings  *)
let traverse_data data =
  let rec find_string_in_data start last count replaced_data =
    let len = String.length !data_from_file in
    match (String.index_from data start '"') with
    | None -> concat_remaining last len replaced_data
    | Some x ->
      (match (String.index_from data (x + 1) '"') with
       | None -> concat_remaining last len replaced_data
       | Some y ->
         let last_start_difference = (y-x) + 1 in
         let fill_space = replace " " "§" (String.sub ~pos:x ~len:last_start_difference data) in
         if x > 0 then (* means there is data before the found double quote
                       so we have to concatenate it*)
           let d = (if count = 0 then
                      (* concats the non string data from between
                      the previous/last found double quote and the
                      beginning of the next string. Anything between the two strings. *)
                   String.concat [(String.sub ~pos:last ~len:(x - last) data); fill_space]
                   else
                   String.concat [replaced_data; (String.sub ~pos:last ~len:(x - last) data); fill_space])
           in
           find_string_in_data (y + 1) (y + 1) (count + 1) d
         else find_string_in_data (y + 1) (y + 1) (count + 1) fill_space);
  in
  find_string_in_data 0 0 0 !data_from_file



let tail_list ls =
  match (List.tl ls) with
  | None -> []
  | Some l -> l

exception Syntax_incorrect
exception No_levels_or_id_returned

let store_node_id id =
  (* id param is a tuple *)
    match id with
    | None -> raise (No_levels_or_id_returned)
    | Some (x, y) -> Hashtbl.add Diagram.branch_id_table x y;
     Some x

(* Goes through each token *)
(* If it encounters a opening paren "(", then it increases
   the level by one. The level count correlates to its hierarchical position
   E.g. level 2 would be the child of a level 1 node,
   which would be the child of level 0*)
(* Anything on level 1 would have the same hierarchical position *)
(* If it encounters a closing paren ")" then it decrements the level *)

let read_tokens tokens levels_count itr_count f tkn_count =
  match (List.hd tokens) with
  | Some ")" -> if itr_count = 0
    then raise (Syntax_incorrect)
    (* print_endline "Syntax error unexpect )" *)
    else let tail = tail_list tokens in
      let levels = levels_count - 1 in (* minus count for closed paren *)
      Hashtbl.remove Diagram.branch_id_table levels_count; (* id is no longer needed *)
      f tail levels (itr_count + 1) tkn_count
  | Some "(" ->
    let tail = tail_list tokens in
    let levels = levels_count + 1 in
    f tail levels (itr_count + 1) tkn_count
  | Some token ->
    Diagram.new_branch (* itr_count *) (* !diagram_node_id *) token levels_count (tkn_count + 1) !tkn
    >>= fun x ->
    store_node_id (Some (levels_count, x))
    |> fun _ -> f (tail_list tokens) levels_count (itr_count + 1) (tkn_count + 1)
  | None -> raise (Syntax_incorrect) (* print_endline "nothing" *)



(* Begins parsing and reading of the file data that we
   initially separated and tokenized *)
exception Token_not_found
let rec tokens_parser tokens levels_count itr_count tkn_count =
  match tokens with
  | [] -> if itr_count = 0
    then raise (Token_not_found)
    else
      (* None here indicates tokens have successfully been parsed *)
      (* And the branches should have been created using read_tokens *)
      print_endline "Diagram created successfully";
    (* return None *)
    exit 0
  | (* tk_list *) _ -> read_tokens tokens levels_count itr_count tokens_parser tkn_count


(* Retrieves temporary coggle token needed for Auth interaction *)
let get_coggle_token code =
  let headers = (Cohttp.Header.of_list Token.create_auth) in
  Cohttp_async.Client.post_form
    ~headers: headers
    ~params:[("code", [code]);
             ("grant_type", ["authorization_code"]);
             ("redirect_uri", ["http://localhost:8080/coggle"])]
    (Uri.of_string "https://coggle.it/token")
    >>= fun (_, body) ->
    Cohttp_async.Body.to_string body
    >>| fun b -> (* changed from >>= *)
    (* printf "yup:  %s\n" b; *)
    Token.parse_token b
    |> fun tk ->
    tkn := tk;
    print_endline ("set: " ^ !tkn);
    tk


(* Extracts coggle authorization code  *)
(* Used for interacting with coggle api *)
let extract req =
  let uri = Cohttp.Request.uri req in
  match Uri.get_query_param uri "code" with
  | Some(code) ->
    if code = "" then
      None (* false *)
    else
      Some code
  | None -> None


(* let test_c = ["("; "begin"; "("; "2nd"; "("; "2.2"; ")"; ")"; *)
(*               "("; "3rd"; ")"; ")"] *)


(* Initiates Coggle interaction by getting Autorization code *)
(* And then get coggle token *)
let init req tokens =
  Random.self_init ();
  extract req
  |> fun code ->
  match code with
  | None -> raise (Code_not_found )
  | Some code ->
    get_coggle_token code
    >>| fun _ -> tokens_parser tokens 0 0 0 (* test_c 0 0 0 *)

let start_server port filename () =
  eprintf "Listening for HTTP on port %d\n" port;
  eprintf "Try 'curl http://localhost:%d/coggle?code=xyz'\n%!" port;
  print_endline "Enter the following url to your browser:";
  print_endline "https://coggle.it/dialog/authorize?response_type=code&scope=read write&client_id=5748885591ce2c8246852e66&redirect_uri=http://localhost:8080/coggle";
  (* let param = ref false in *)
  (* let inet_addr = ref None in *)
  Cohttp_async.Server.create ~on_handler_error:`Raise
    (Tcp.on_port port)
    (fun ~body: _ _sock req ->
       let uri = Cohttp.Request.uri req in
       match Uri.path uri with
       | "/coggle" ->
         (* extract req *)
         In_channel.read_all filename
         |> traverse_data
         |> tokenize
         |> List.filter ~f:(fun x -> x <> "\n")
         |> List.map ~f:(fun current -> replace  "§" " " current)
         |> init req (* test_c *)
         |> (fun _ ->
             match !inet_addr with
             | None -> Cohttp_async.Server.respond_with_string "inet address not found"
             | _ (* Some y *) ->
               (* Cohttp_async.Server.close y *)
               (* |> fun _ -> *)
               (* print_endline "Received Authorization code"; *)
               (* print_endline "Closing server"; *)
               Cohttp_async.Server.respond_with_string "Received Authorization code \n"
               (* fun _ -> print_endline "hshs" *)
               (* (Cohttp_async.Server.close y) *))
       | _ -> Cohttp_async.Server.respond_with_string ~code:`Not_found "Route not found\n"
    )
  >>= (fun addr -> let set_inet =
                     inet_addr := Some addr;
        in Deferred.never
          set_inet)


let () =
  Command.async
    ~summary:"Start Async server"
    Command.Spec.(empty
                  +> flag "-p" (optional_with_default 8080 int)
                    ~doc:"int Source port to listen on"
                  +> anon ("filename" %: string)
                 ) start_server
  |> Command.run


