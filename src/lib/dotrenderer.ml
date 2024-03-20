open Astring
module DataFile = Ast.DataFile
module DataFileSet = Set.Make (DataFile)

(* In theory this could be a recursive structure that attempts to maintain the
    heirarchy of the document, markdown doesn't enforce that the section levels
    make any sort of sense, so for now I'm just going to assume a single level.

    I did initially try to implement that but got a lot of complexity for little
   initial benefit. *)
type section_group = { name : string; children : Block.t list }

let render_command_to_dot ppf command =
  (* let node_style = process_style node.style in *)
  (* TODO - some commands like littlejohn get different box styles*)
  let process_index = Ast.Leaf.id command in
  List.iter
    (fun datafile ->
      Format.fprintf ppf "\tn%d->n%d[penwidth=\"2.0\"];\n"
        (DataFile.id datafile) process_index)
    (Ast.Leaf.inputs command);
  Format.fprintf ppf "\tn%d[shape=\"%s\",label=\"%s\"];\n" process_index "box"
    (Uri.pct_encode (Command.name (Ast.Leaf.command command)));
  List.iter
    (fun datafile ->
      Format.fprintf ppf "\tn%d->n%d[penwidth=\"2.0\"];\n" process_index
        (DataFile.id datafile))
    (Ast.Leaf.outputs command);
  Format.fprintf ppf "\n"

let datafile_to_dot ppf datafile =
  Format.fprintf ppf "\tn%d[shape=\"cylinder\",label=\"%s\"];\n"
    (DataFile.id datafile) (DataFile.path datafile)

let render_ast_to_dot ppf ast : unit =
  Format.fprintf ppf "digraph{\n";
  List.concat_map
    (fun group ->
      let commands = Ast.CommandGroup.children group in
      List.concat_map
        (fun command ->
          let inputs = Ast.Leaf.inputs command
          and outputs = Ast.Leaf.outputs command in
          List.concat [ inputs; outputs ])
        commands)
    ast
  |> DataFileSet.of_list
  |> DataFileSet.iter (datafile_to_dot ppf);

  List.iteri
    (fun i group ->
      let name = Ast.CommandGroup.name group
      and commands = Ast.CommandGroup.children group in
      Format.fprintf ppf "subgraph \"cluster_%d\" {\n" i;
      Format.fprintf ppf "\tlabel = \"%s\"\n" name;
      List.iter (render_command_to_dot ppf) commands;
      Format.fprintf ppf "}\n")
    ast;
  Format.fprintf ppf "}\n"

let parse_frontmatter frontmatter =
  match Frontmatter.of_string frontmatter with
  | Ok frontmatter -> frontmatter
  | Error (`Msg m) -> failwith ("Failed to parse frontmatter: " ^ m)

let default ~info ~body = Some (Block.v ~alias:info ~body `Run)

let parse_markdown markdown =
  let doc = Cmarkit.Doc.of_string markdown in

  let current_section_title = ref "Top level"
  and cuirrent_block_list = ref []
  and sections = ref [] in

  let block _ = function
    | Cmarkit.Block.Heading (node, _meta) ->
        let title =
          Cmarkit.Block.Heading.inline node
          |> Cmarkit.Inline.to_plain_text ~break_on_soft:false
          |> List.map (String.concat ~sep:"")
          |> String.concat ~sep:" / "
        in
        (if List.length !cuirrent_block_list > 0 then
           let order_corrected_group = List.rev !cuirrent_block_list in
           sections :=
             { name = !current_section_title; children = order_corrected_group }
             :: !sections);
        cuirrent_block_list := [];
        current_section_title := title;
        `Default
    | Cmarkit.Block.Code_block (node, _meta) ->
        let info_str =
          match Cmarkit.Block.Code_block.info_string node with
          | None -> "shark-run:"
          | Some (info_str, _) -> info_str
        in
        let body = Cmarkit.Block.Code_block.code node in
        let body =
          List.map Cmarkit.Block_line.to_string body
          |> List.map String.trim |> String.concat ~sep:"\n"
        in
        (match Block.of_info_string ~default ~body info_str with
        | Some b -> cuirrent_block_list := b :: !cuirrent_block_list
        | None -> ());
        `Default
    | _ -> `Default
  in

  let mapper = Cmarkit.Mapper.make ~block () in
  ignore (Cmarkit.Mapper.map_doc mapper doc);

  (* Flush last section *)
  (if List.length !cuirrent_block_list > 0 then
     let order_corrected_group = List.rev !cuirrent_block_list in
     sections :=
       { name = !current_section_title; children = order_corrected_group }
       :: !sections);

  List.rev !sections

let render ~template_markdown =
  let metadata, sections =
    match String.cuts ~sep:"---" template_markdown with
    | [ frontmatter; markdown ] | [ ""; frontmatter; markdown ] ->
        (parse_frontmatter frontmatter, parse_markdown markdown)
    | [ markdown ] -> (Frontmatter.empty, parse_markdown markdown)
    | _ -> failwith "Malformed frontmatter/markdown file"
  in
  List.map
    (fun sgroup ->
      ( sgroup.name,
        List.map Block.command_list sgroup.children
        |> List.concat
        |> List.filter_map Command.of_string
        |> List.filter_map (fun c ->
               match Command.file_args c with [] -> None | _ -> Some c) ))
    sections
  |> Ast.order_command_list metadata
  |> render_ast_to_dot Format.str_formatter;
  Format.flush_str_formatter ()
