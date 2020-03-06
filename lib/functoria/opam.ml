(*
 * Copyright (c) 2013-2020 Thomas Gazagnaire <thomas@gazagnaire.org>
 * Copyright (c) 2013-2020 Anil Madhavapeddy <anil@recoil.org>
 * Copyright (c) 2015-2020 Gabriel Radanne <drupyog@zoho.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

let find_git () =
  let open Rresult in
  let is_git p = Bos.OS.Dir.exists Fpath.(p / ".git") in
  let app_opt p d = match p with None -> d | Some p -> Fpath.(d // p) in
  let rec find p path =
    if Fpath.is_root p then Error (`Msg "no git repo found, reached root")
    else
      is_git p >>= fun has_git ->
      if has_git then Ok path
      else find (Fpath.parent p) (Some (app_opt path (Fpath.base p)))
  in
  Bos.OS.Dir.current () >>= fun cwd ->
  find cwd None >>= fun subdir ->
  let git_branch = Bos.Cmd.(v "git" % "rev-parse" % "--abbrev-ref" % "HEAD") in
  Bos.OS.Cmd.(run_out git_branch |> out_string) >>= fun (branch, _) ->
  let git_remote = Bos.Cmd.(v "git" % "remote" % "get-url" % "origin") in
  Bos.OS.Cmd.(run_out git_remote |> out_string) >>| fun (git_url, _) ->
  (subdir, branch, git_url)

type t = {
  name : string;
  depends : Package.t list;
  build : string list;
  pins : (string * string) list;
  src : string option;
}

let guess_src () =
  let git_info =
    match find_git () with
    | Error _ -> None
    | Ok (_, branch, git_url) -> Some (branch, git_url)
  in
  match git_info with
  | None -> None
  | Some (branch, origin) ->
      (* TODO is there a library for git urls anywhere? *)
      let public =
        match Astring.String.cut ~sep:"github.com:" origin with
        | Some (_, post) -> "git+https://github.com/" ^ post
        | _ -> origin
      in
      Some (Fmt.str "%s#%s" public branch)

let v ?(build = []) ?(depends = []) ?(pins = []) ~src name =
  let src =
    match src with `Auto -> guess_src () | `None -> None | `Some d -> Some d
  in
  { name; depends; build; pins; src }

let pp_packages ppf packages =
  Fmt.pf ppf "\n  %a\n"
    Fmt.(list ~sep:(unit "\n  ") (Package.pp ~surround:"\""))
    packages

let pp_pins ppf = function
  | [] -> ()
  | pins ->
      let pp_pin ppf (package, url) =
        Fmt.pf ppf "[\"%s.dev\" %S]" package url
      in
      Fmt.pf ppf "@.pin-depends: [ @[<hv>%a@]@ ]@."
        Fmt.(list ~sep:(unit "@ ") pp_pin)
        pins

let pp_src ppf = function
  | None -> ()
  | Some src -> Fmt.pf ppf {|@.url { src: %S }|} src

let pp ppf t =
  let pp_build = Fmt.list ~sep:(Fmt.unit " ") (Fmt.fmt "%S") in
  Fmt.pf ppf
    {|# %s

opam-version: "2.0"
name: "%s"
maintainer: "dummy"
authors: "dummy"
homepage: "dummy"
bug-reports: "dummy"
synopsis: "This is a dummy"

build: [%a]

depends: [%a]
%a%a
|}
    (Codegen.generated_header ())
    t.name pp_build t.build pp_packages t.depends pp_src t.src pp_pins t.pins
