let safe_char = function
  | 'A'..'Z' | 'a'..'z' | '0'..'9' | '-' | '_' -> true
  | _ -> false

let check_safe s =
  if not (Astring.String.for_all safe_char s) then
    Fmt.failwith "Unsafe characters in %S" s

let build_cache repo =
  let { Current_github.Repo_id.owner; name } = repo in
  check_safe owner;
  check_safe name;
  let name = Printf.sprintf "dune:%s:%s" owner name in
  Obuilder_spec.Cache.v name ~target:"/src/_build" ~buildkit_options:["sharing", "private"]

let install_opam_tools ~network ~cache =
  let opam_tools_hash = "6c56ab9fedd7b3f6c143cb606a0ea6fe6a384013" in
  let open Obuilder_spec in
  [
    run ~network ~cache "opam pin add -n https://github.com/avsm/opam-tools.git#%s" opam_tools_hash;
    run ~network ~cache "opam depext -iy opam-tools"
  ]

let spec ~base ~repo ~opam_files ~variant =
  let download_cache = Obuilder_spec.Cache.v Opam_build.download_cache ~target:"/home/opam/.opam/download-cache" in
  let network = ["host"] in
  let dune_cache = build_cache repo in
  let duniverse_hash = "375e5a2feeace010dd3ba4b54058a28f2bdf32ab" in
  let tools = "ocamlformat,merlin,mdx,dune.2.6.2,odoc,ocaml-lsp-server,dune-release,duniverse" in
  let open Obuilder_spec in
  stage ~from:base @@ [
    comment "%s" (Variant.to_string variant);
    user ~uid:1000 ~gid:1000
  ] @ install_opam_tools ~network ~cache:[download_cache] @ [
    workdir "/src";
    run "sudo chown opam /src";
    copy opam_files ~dst:"/src/";
    run ~network ~cache:[download_cache] "sudo apt-get update && sudo apt-get -y install pkg-config";
    run ~network ~cache:[download_cache] "opam tools --no-install --pin-tool=duniverse,https://github.com/ocamllabs/duniverse.git#%s --tools=%s --compiler `opam exec -- ocamlc -version` -vv" duniverse_hash tools;
    copy ["dune-get"] ~dst:"/src/";
    (* TODO make duniverse depext install the package as opam-depext does *)
    run ~network ~cache:[download_cache] "sudo apt-get update && sudo apt-get -y install build-essential `opam exec -- duniverse depext`";
    run ~network ~cache:[download_cache] "opam exec -- duniverse pull";
    copy ["."] ~dst:"/src/";
    run ~cache:[dune_cache] "opam exec -- dune build @install";
    run ~cache:[dune_cache] "opam exec -- dune runtest";
  ]
