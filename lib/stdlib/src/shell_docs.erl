%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 1996-2025. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%
-module(shell_docs).
-moduledoc """
Functions used to render [EEP-48](`e:kernel:eep48_chapter.md`) style documentation for a shell.

This module can be used to render function and type documentation to be printed
in a shell. This is the module that is used to render the documentation accessed through
the shell through [`c:h/1,2,3`](`\\c:h/1`). Example:

```txt
1> h(maps,new,0).

  -spec new() -> Map when Map :: #{}.

Since:
  OTP 17.0

  Returns a new empty map.

  Example:

    > maps:new().
    #{}
```

This module formats and renders EEP-48 documentation of the format
`application/erlang+html`. For more information about this format see
[Documentation Storage](`e:edoc:doc_storage.md`) in EDoc's User's
Guide. It can also render any other format of "text" type, although those will
be rendered as is.
""".
-moduledoc(#{since => "OTP 23.0"}).

%% This module takes care of rendering and normalization of
%% application/erlang+html style documentation.


%% IMPORTANT!!
%% When changing the rendering in the module, there are no tests as such
%% that you do not break anything else. So you should use the function
%% shell_docs_SUITE:render_all(Dir) to write all documentation to that
%% folder and then you can use `diff -b` to see if you inadvertently changed
%% something.

-include_lib("kernel/include/eep48.hrl").

-export([render/2, render/3, render/4, render/5]).
-export([render_type/2, render_type/3, render_type/4, render_type/5]).
-export([render_callback/2, render_callback/3, render_callback/4, render_callback/5]).

-export([test/2]).

%% Used by chunks.escript in erl_docgen
-export([validate/1, normalize/1, supported_tags/0]).

%% Convenience functions
-export([get_doc/1, get_doc/3, get_type_doc/3, get_callback_doc/3]).

-export_type([chunk_elements/0, chunk_element_attr/0]).

-record(config, { docs,
                  module,
                  encoding,
                  ansi,
                  io_opts = io:getopts(),
                  columns
                }).

-define(ALL_ELEMENTS,[a,p,'div',blockquote,br,h1,h2,h3,h4,h5,h6,
                      i,b,em,strong,pre,code,ul,ol,li,dl,dt,dd]).
%% inline elements are:
-define(INLINE,[i,b,em,strong,code,a]).
-define(IS_INLINE(ELEM),(((ELEM) =:= a) orelse ((ELEM) =:= code)
                         orelse ((ELEM) =:= i) orelse ((ELEM) =:= em)
                         orelse ((ELEM) =:= b) orelse ((ELEM) =:= strong))).
%% non-inline elements are:
-define(BLOCK,[p,'div',pre,blockquote,br,ul,ol,li,dl,dt,dd,h1,h2,h3,h4,h5,h6]).
-define(IS_BLOCK(ELEM),not ?IS_INLINE(ELEM)).
-define(IS_PRE(ELEM),(((ELEM) =:= pre))).

%% If you update the below types, make sure to update the documentation in
%% erl_docgen/doc/src/doc_storage.xml as well!!!
-doc """
The record holding EEP-48 documentation for a module. You can use
`code:get_doc/1` to fetch this information from a module.
""".
-type docs_v1() :: #docs_v1{}.
-doc """
The configuration of how the documentation should be rendered.

- **encoding** - Configure the encoding that should be used by the renderer for
  graphical details such as bullet-points. By default `shell_docs` uses the
  value returned by [`io:getopts()`](`io:getopts/0`).

- **ansi** - Configure whether
  [ansi escape codes](https://en.wikipedia.org/wiki/ANSI_escape_code) should be
  used to render graphical details such as bold and underscore. By default
  `shell_docs` will try to determine if the receiving shell supports ansi escape
  codes. It is possible to override the automated check by setting the kernel
  configuration parameter `shell_docs_ansi` to a `t:boolean/0` value.

- **columns** - Configure how wide the target documentation should be rendered.
  By default `shell_docs` used the value returned by
  [`io:columns()`](`io:columns/0`). It is possible to override this default
  by setting the stdlib configuration parameter `shell_docs_columns`
  to a `t:pos_integer/0` value.
""".
-doc #{ since => ~"OTP 23.2" }.
-type config() :: #{ encoding => unicode | latin1,
                     columns => pos_integer(),
                     ansi => boolean() }.
-type chunk_elements() :: [chunk_element()].
-type chunk_element() :: {chunk_element_type(),chunk_element_attrs(),
                          chunk_elements()} | binary().
-type chunk_element_attrs() :: [chunk_element_attr()].
-type chunk_element_attr() :: {atom(),unicode:chardata()}.
-doc "The HTML tags allowed in `application/erlang+html`.".
-type chunk_element_type() :: chunk_element_inline_type() | chunk_element_block_type().
-type chunk_element_inline_type() :: a | code | em | strong | i | b.
-type chunk_element_block_type() :: p | 'div' | blockquote | br | pre | ul |
                                    ol | li | dl | dt | dd |
                                    h1 | h2 | h3 | h4 | h5 | h6.

-doc """
This function can be used to find out which tags are supported by
`application/erlang+html` documentation.
""".
-doc(#{since => <<"OTP 24.0">>}).
-spec supported_tags() -> [chunk_element_type()].
supported_tags() ->
    ?ALL_ELEMENTS.

-doc """
This function can be used to do a basic validation of the doc content of
`application/erlang+html` format.
""".
-doc(#{since => <<"OTP 23.0">>}).
-spec validate(Module) -> ok when
      Module :: module() | docs_v1().
%% Simple validation of erlang doc chunk. Check that all tags are supported and
%% that the signature is correct.
validate(Module) when is_atom(Module) ->
    {ok, Doc} = code:get_doc(Module),
    validate(Doc);
validate(#docs_v1{ format = ?NATIVE_FORMAT, module_doc = MDocs, docs = AllDocs }) ->

    %% Check some macro in-variants
    AE = lists:sort(?ALL_ELEMENTS),
    AE = lists:sort(?INLINE ++ ?BLOCK),
    true = lists:all(fun(Elem) -> ?IS_INLINE(Elem) end, ?INLINE),
    true = lists:all(fun(Elem) -> ?IS_BLOCK(Elem) end, ?BLOCK),

    _ = validate_docs(MDocs),
    lists:foreach(fun({_,_Anno, Sig, Docs, _Meta}) ->
                          case lists:all(fun erlang:is_binary/1, Sig) of
                              false -> throw({invalid_signature,Sig});
                              true -> ok
                          end,
                          validate_docs(Docs)
                  end, AllDocs),
    ok.

validate_docs(hidden) ->
    ok;
validate_docs(none) ->
    ok;
validate_docs(#{} = MDocs) ->
    maps:foreach(fun(_Key,MDoc) -> validate_docs(MDoc,[]) end, MDocs),
    ok.
validate_docs([H|T],Path) when is_tuple(H) ->
    _ = validate_docs(H,Path),
    validate_docs(T,Path);
validate_docs({br,Attr,Content} = Br,Path) ->
    if Attr =:= [], Content =:= [] ->
            ok;
       true ->
            throw({content_to_allowed_in_br,Br,Path})
    end;
validate_docs({Tag,Attr,Content},Path) ->

    %% Test that we only have li's within ul and ol
    case (Tag =/= li) andalso (length(Path) > 0) andalso ((hd(Path) =:= ul) orelse (hd(Path) =:= ol)) of
        true ->
            throw({only_li_allowed_within_ul_or_ol,Tag,Path});
        _ ->
            ok
    end,

    %% Test that we only have dd's and dt's within dl
    case (Tag =/= dd) andalso (Tag =/= dt) andalso (length(Path) > 0) andalso (hd(Path) =:= dl) of
        true ->
            throw({only_dd_or_dt_allowed_within_dl,Tag,Path});
        _ ->
            ok
    end,

    %% Test that we do not have p's within p's
    case Tag =:= p andalso lists:member(p, Path) of
        true ->
            throw({nested_p_not_allowed,Tag,Path});
        false ->
            ok
    end,
    %% Test that there are no block tags within a pre, h*
    case lists:member(pre,Path) or
        lists:any(fun(H) -> lists:member(H,Path) end, [h1,h2,h3,h4,h5,h6]) of
        true when ?IS_BLOCK(Tag) ->
            throw({cannot_put_block_tag_within_pre,Tag,Path});
        _ ->
            ok
    end,
    %% Test that a block tag is not within an inline tag
    case lists:member(Tag,?BLOCK) of
        true ->
            case lists:any(fun(P) -> ?IS_INLINE(P) end, Path) of
                true ->
                    throw({cannot_put_inline_tag_outside_block, Tag, Path});
                false ->
                    ok
            end;
        false ->
            ok
    end,
    case lists:member(Tag,?ALL_ELEMENTS) of
        false ->
            throw({invalid_tag,Tag,Path});
        true ->
            ok
    end,
    case lists:all(fun({Key,Val}) -> is_atom(Key) andalso is_binary(Val) end,Attr) of
        true -> ok;
        false -> throw({invalid_attribute,{Tag,Attr}})
    end,
    validate_docs(Content,[Tag | Path]);
validate_docs([Chars | T], Path) when is_binary(Chars) ->
    validate_docs(T, Path);
validate_docs([],_) ->
    ok.

%% Follows algorithm described here:
%% * https://medium.com/@patrickbrosset/when-does-white-space-matter-in-html-b90e8a7cdd33
%% which in turn follows this:
%% * https://www.w3.org/TR/css-text-3/#white-space-processing
-doc """
This function can be used to do whitespace normalization of
`application/erlang+html` documentation.
""".
-doc(#{since => <<"OTP 23.0">>}).
-spec normalize(Docs) -> NormalizedDocs when
      Docs :: chunk_elements(),
      NormalizedDocs :: chunk_elements().
normalize(Docs) ->
    Trimmed = normalize_trim(Docs,true),
    Space = normalize_space(Trimmed),
    normalize_paragraph(Space).

normalize_trim(Bin,true) when is_binary(Bin) ->
    %% Remove any whitespace (except \n) before or after a newline
    NoSpace = re:replace(Bin,"[^\\S\n]*\n+[^\\S\n]*","\n",[unicode,global]),
    %% Replace any tabs with space
    NoTab = re:replace(NoSpace,"\t"," ",[unicode,global]),
    %% Replace any newlines with space
    NoNewLine = re:replace(NoTab,"\\v"," ",[unicode,global]),
    %% Replace any sequences of \s with a single " "
    re:replace(NoNewLine,"\\s+"," ",[unicode,global,{return,binary}]);
normalize_trim(Bin,false) when is_binary(Bin) ->
    Bin;
normalize_trim([{code,Attr,Content}|T],false) ->
    TrimmedContent =
        case lists:reverse(normalize_trim(Content,false)) of
            %% When in a <pre><code>, we strip the trailing
            %% whitespace from the last binary.
            [Bin|Rest] when is_binary(Bin) ->
                lists:reverse([string:trim(Bin,trailing) | Rest]);
            Else ->
                lists:reverse(Else)
        end,
    [{code,Attr,TrimmedContent} | normalize_trim(T,false)];
normalize_trim([{pre,Attr,Content}|T],Trim) ->
    [{pre,Attr,normalize_trim(Content,false)} | normalize_trim(T,Trim)];
normalize_trim([{Tag,Attr,Content}|T],Trim) ->
    [{Tag,Attr,normalize_trim(Content,Trim)} | normalize_trim(T,Trim)];
normalize_trim([<<>>|T],Trim) ->
    normalize_trim(T,Trim);
normalize_trim([B1,B2|T],Trim) when is_binary(B1),is_binary(B2) ->
    normalize_trim([<<B1/binary,B2/binary>> | T],Trim);
normalize_trim([H|T],Trim) ->
    [normalize_trim(H,Trim) | normalize_trim(T,Trim)];
normalize_trim([],_Trim) ->
    [].

%% We want to remove any duplicate spaces, even if they
%% cross into other inline elements.
%% For non-inline elements we just need to make sure that any
%% leading or trailing spaces are stripped.
normalize_space([{Pre,Attr,Content}|T]) when ?IS_PRE(Pre) ->
    [{Pre,Attr,trim_first_and_last(Content,$\n)} | normalize_space(T)];
normalize_space([{Block,Attr,Content}|T]) when ?IS_BLOCK(Block) ->
    [{Block,Attr,normalize_space(Content)} | normalize_space(T)];
normalize_space([]) ->
    [];
normalize_space(Elems) ->
    {InlineElems, T} =
        lists:splitwith(fun(E) ->
                                is_binary(E) orelse (is_tuple(E) andalso ?IS_INLINE(element(1,E)))
                        end, Elems),
    trim_inline(InlineElems) ++ normalize_space(T).

trim_inline(Content) ->
    {NewContent,_} = trim_inline(Content,false),
    trim_first_and_last(NewContent,$ ).
trim_inline([Bin|T],false) when is_binary(Bin) ->
    LastElem = binary:at(Bin,byte_size(Bin)-1),
    case trim_inline(T,LastElem =:= $ ) of
        {[B2 | NewT],NewState} when is_binary(B2) ->
            {[<<Bin/binary,B2/binary>>|NewT],NewState};
        {NewT, NewState} ->
            {[Bin|NewT],NewState}
    end;
trim_inline([<<" ">>|T],true) ->
    trim_inline(T,true);
trim_inline([<<" ",Bin/binary>>|T],true) when is_binary(Bin) ->
    trim_inline([Bin | T],true);
trim_inline([Bin|T],true) when is_binary(Bin) ->
    trim_inline([Bin|T],false);
trim_inline([{Elem,Attr,Content}|T],TrimSpace) ->
    {NewContent,ContentTrimSpace} = trim_inline(Content,TrimSpace),
    {NewT,TTrimSpace} = trim_inline(T,ContentTrimSpace),
    IsAnchor = (Elem =:= a) andalso proplists:is_defined(id,Attr),
    if NewContent == [] andalso (not IsAnchor) ->
            %% Remove if all content has been trimmed and this is not an anchor
            {NewT, TTrimSpace};
       true ->
            {[{Elem,Attr,NewContent} | NewT], TTrimSpace}
    end;
trim_inline([],TrimSpace) ->
    {[],TrimSpace}.


%% This function removes the first and last What from the content.
%% This is complicated by the fact that the first or last element
%% may not have any binary, or have the binary deeply nested within.
trim_first_and_last(Content, What) when What < 256 ->
    {FirstTrimmed, _} = trim_first(Content,What),
    {LastTrimmed, _} = trim_last(FirstTrimmed,What),
    LastTrimmed.

trim_first([Bin|T],What) when is_binary(Bin) ->
    case Bin of
        <<What>> ->
            {T,true};
        <<What,NewBin/binary>> ->
            {[NewBin|T],true};
        Bin ->
            {[Bin|T],true}
    end;
trim_first([{Elem,Attr,Content} = Tag|T],What) ->
    case trim_first(Content,What) of
        {[],true} ->
            {T,true};
        {NewContent,true} ->
            {[{Elem,Attr,NewContent}|T],true};
        {Content,false} ->
            {NewT,NewState} = trim_first(T,What),
            {[Tag | NewT],NewState}
    end;
trim_first([],_What) ->
    {[],false}.

trim_last([Bin | T],What) when is_binary(Bin) ->
    case trim_last(T,What) of
        {NewT,true} ->
            {[Bin | NewT],true};
        {T,false} ->
            PreSz = byte_size(Bin)-1,
            case Bin of
                <<What>> -> {T,true};
                <<NewBin:PreSz/binary,What>> ->
                    {[NewBin|T],true};
                Bin ->
                    {[Bin|T],true}
            end
    end;
trim_last([{Elem,Attr,Content} = Tag|T],What) ->
    case trim_last(T,What) of
        {NewT,true} ->
            {[Tag | NewT],true};
        {T,false} ->
            case trim_last(Content,What) of
                {[],true} ->
                    %% If the content became empty and we processed some text
                    %% we remove the element.
                    {[],true};
                {NewContent,NewState} ->
                    {[{Elem,Attr,NewContent}|T],NewState}
            end
    end;
trim_last([],_What) ->
    {[],false}.

%% Any non-block elements at top level are wrapped in a p so that tools
%% don't have to deal with that.
normalize_paragraph([{Tag,_,_} = Block | T]) when ?IS_BLOCK(Tag) ->
    [Block | normalize_paragraph(T)];
normalize_paragraph([{_,_,[]} = NoContent | T]) ->
    %% If an inline tag has no content we don't wrap it in a <p>. This is
    %% aimed at fixing <a id=""/> tags at top-level.
    [NoContent | normalize_paragraph(T)];
normalize_paragraph([]) ->
    [];
normalize_paragraph(Elems) ->
    case lists:splitwith(
           fun(E) ->
                   is_binary(E) orelse
                     (?IS_INLINE(element(1, E)) andalso element(3, E) =/= [])
           end, Elems) of
        {NotP, P} ->
            [{p,[],NotP} | normalize_paragraph(P)]
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% API function for dealing with the function documentation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-doc false.
-spec get_doc(Module :: module()) -> chunk_elements().
get_doc(Module) ->
    {ok, #docs_v1{ module_doc = ModuleDoc } = D} = code:get_doc(Module),
    get_local_doc(Module, ModuleDoc, D).

-doc false.
-spec get_doc(Module :: module(), Function, Arity) ->
          [{{function, Function,Arity}, Anno, Signature, chunk_elements(), Metadata}] when
      Function :: atom(),
      Arity :: arity(),
      Anno :: erl_anno:anno(),
      Signature :: [binary()],
      Metadata :: map().
get_doc(Module, Function, Arity) ->
    {ok, #docs_v1{ docs = Docs } = D}  = code:get_doc(Module),
    Map = fun ({F,A,S,Dc,M}) -> {F,A,S,get_local_doc(F, Dc, D),M} end,
    filtermap_mfa({function, Function, Arity}, Map, Docs).

-doc false.
-spec test(module(), [{{function | type | callback, atom(), non_neg_integer()}
                      | module_doc, erl_eval:binding_struct()}]) -> ok.
test(Module, Bindings) ->
    case code:get_doc(Module) of
        {ok, #docs_v1{ format = ~"text/markdown" } = Docs} ->
            shell_docs_test:module(Docs, Bindings);
        {ok, _} ->
            {error, unsupported_format};
        Else ->
            Else
    end.

-doc(#{equiv => render(Module, Docs, #{})}).
-doc(#{since => <<"OTP 23.0">>}).
-spec render(Module, Docs) -> unicode:chardata() when
      Module :: module(),
      Docs :: docs_v1().
render(Module, #docs_v1{ } = D) when is_atom(Module) ->
    render(Module, D, #{}).

config_module(Module, Config) when is_map(Config) ->
  Config#{module => Module};
config_module(Module, #config{}=Config) ->
  Config#config{module = Module}.

-doc """
render(Module, DocsOrFunction, ConfigOrDocs)

Render module or function documentation.

Renders the module documentation if called as `render(Module, Docs, Config)`.

Equivalent to [`render(Module, Function, Docs, #{})`](`render/4`) if called
as `render(Module, Function, Docs)`.
""".
-doc(#{since => <<"OTP 23.0">>}).
-spec render(Module, Docs, Config) -> unicode:chardata() when
      Module :: module(),
      Docs :: docs_v1(),
      Config :: config();

            (Module, Function, Docs) -> Res when
      Module :: module(),
      Function :: atom(),
      Docs :: docs_v1(),
      Res :: unicode:chardata() | {error,function_missing}.
render(Module, #docs_v1{module_doc = ModuleDoc} = D, Config)
  when is_atom(Module), is_map(Config) ->
    Config0 = config_module(Module, Config),
    render_headers_and_docs([[{h2,[],[<<"\t",(atom_to_binary(Module))/binary>>]}]],
                            get_local_doc(Module, ModuleDoc, D), D, Config0);
render(_Module, Function, #docs_v1{ } = D) ->
    render(_Module, Function, D, #{}).

-doc """
render(Module, Function, DocsOrArity, ConfigOrDocs)

Render function documentation.

Renders the function documentation if called as `render(Module, Function, Docs, Config)`.

Equivalent to [`render(Module, Function, Arity, Docs, #{})`](`render/4`) if called
as `render(Module, Function, Arity, Docs)`.
""".
-doc(#{since => <<"OTP 23.0">>}).
-spec render(Module, Function, Docs, Config) -> Res when
      Module :: module(),
      Function :: atom(),
      Docs :: docs_v1(),
      Config :: config(),
      Res :: unicode:chardata() | {error,function_missing};

            (Module, Function, Arity, Docs) -> Res when
      Module :: module(),
      Function :: atom(),
      Arity :: arity(),
      Docs :: docs_v1(),
      Res :: unicode:chardata() | {error,function_missing}.
render(Module, Function, D, Config)
    when is_atom(Module), is_atom(Function), is_map(Config) ->
    render_fn(Module, Function, none, D, Config);
render(_Module, Function, Arity, D) ->
    render_fn(_Module, Function, Arity, D, #{}).

-doc "Render the documentation for a function.".
-doc(#{since => <<"OTP 23.2">>}).
-spec render(Module, Function, Arity, Docs, Config) -> Res when
      Module :: module(),
      Function :: atom(),
      Arity :: arity(),
      Docs :: docs_v1(),
      Config :: config(),
      Res :: unicode:chardata() | {error,function_missing}.
render(Module, Function, Arity, #docs_v1{ }=DocV1, Config)
  when is_atom(Module), is_atom(Function), is_integer(Arity),  is_map(Config) ->
    render_fn(Module, Function, Arity, DocV1, Config).

%% this function resembles render/5 except that the type allows
%% 'Arity :: arity() | none()'. The reason for doing this is to
%% not change existing type specs and to cascade calls from render/2, render/3,
%% and render/4 into a general function that performs all the work.
-spec render_fn(Module, Function, Arity, Docs, Config) -> Res when
      Module :: module(),
      Function :: atom(),
      Arity :: arity() | none,
      Docs :: docs_v1(),
      Config :: config(),
      Res :: unicode:chardata() | {error,function_missing}.
render_fn(Module, Function, Arity, DocV1, Config) ->
    renderer(Config, {Module, function, Function, Arity}, DocV1).

%% general funtion that performs rendering of functions, types, and callback
renderer(Config0, {Module, Kind, Name, Arity}, #docs_v1{ docs = Docs }=DocV1) ->
  Config = config_module(Module, Config0),
  FnFunctions = filter_mfa({Kind, Name, Arity}, Docs),
  Fn = dispatch_renderer(Kind),
  Fn(FnFunctions, DocV1, Config).

dispatch_renderer(function) -> fun render_function/3;
dispatch_renderer(type) -> fun render_typecb_docs/3;
dispatch_renderer(callback) -> fun render_typecb_docs/3.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% API function for dealing with the type documentation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-doc false.
-spec get_type_doc(Module :: module(), Type :: atom(), Arity :: arity()) ->
          [{{type, Type,Arity}, Anno, Signature, chunk_elements(), Metadata}] when
      Type :: atom(),
      Arity :: arity(),
      Anno :: erl_anno:anno(),
      Signature :: [binary()],
      Metadata :: map().
get_type_doc(Module, Type, Arity) ->
    {ok, #docs_v1{ docs = Docs } = D} = code:get_doc(Module),
    Map = fun ({F,A,S,Dc,M}) -> {F,A,S,get_local_doc(F, Dc, D),M} end,
    filtermap_mfa({type, Type, Arity}, Map, Docs).

-doc(#{equiv => render_type(Module, Docs, #{})}).
-doc(#{since => <<"OTP 23.0">>}).
-spec render_type(Module, Docs) -> unicode:chardata() when
      Module :: module(),
      Docs :: docs_v1().
render_type(Module, D) ->
  render_type(Module, D, #{}).

%% extract AST raw type specifications.
extract_type_specs(Module) ->
  maybe
    Path = find_path(Module),
    true ?= non_existing =/= Path,
    {ok, {Module,
           [{abstract_code,
             {raw_abstract_v1,AST}}]}} ?= beam_lib:chunks(Path, [abstract_code]),

    %% the mapping keys 'type', 'function', and 'callback' correspond
    %% to existing EEP-48 {**Kind**, Name, Arity} format, where Kind
    %% ranges over these values. This is needed to differentiate
    %% function, callback, and types when looking up their type specs
    Acc = #{type => #{}, 'function' => #{}, 'callback' => #{}},
    lists:foldl(fun filter_exported_types/2, Acc, AST)
  else
    false -> #{}; % when non_existing =/= Path,
    {ok, {Module, [{abstract_code, no_abstract_code}]}} -> #{}; % from beam_lib:chunks/1
    {error,beam_lib,{file_error,_,_}} -> #{} % from beam_lib:chunks/1
  end.

-spec find_path(Mod :: module()) -> non_existing | file:filename_all().
find_path(Module) ->
    maybe
      %% This is set to non_existing by tests to generate docs without any specs
      undefined ?= get({?MODULE, nospecs}),
      preloaded ?= code:which(Module),
      PreloadedPath = filename:join(code:lib_dir(erts),"ebin"),
      filename:join(PreloadedPath, atom_to_list(Module) ++ ".beam")
    else
      Other -> Other
    end.

%%
%% Raw Abstract syntax tree maps:
%% - type => type,
%% - opaque => type,
%% - spec => function
%% - callback => callback
%%
filter_exported_types({attribute, _An, Type, {Name,_Rhs,Lhs}}=Spec, #{type := Types}=Acc)
  when Type =:= type; Type =:= opaque ->
  Acc#{type => Types#{{Name, length(Lhs)} => Spec}};
filter_exported_types({attribute, _An, spec, {{Name,Arity}, _}}=Spec, #{function := Types}=Acc) ->
  Acc#{function => Types#{{Name, Arity} => Spec}};
filter_exported_types({attribute, _An, spec, {{_Mod,Name,_Arity}, Args}}, Acc) ->
  filter_exported_types({attribute, _An, spec, {{Name,_Arity}, Args}}, Acc);
filter_exported_types({attribute, _An, callback, {{Name,Arity}, _}}=Spec, #{callback := Types}=Acc) ->
  Acc#{function => Types#{{Name, Arity} => Spec}};
filter_exported_types(_, Acc) ->
  Acc.


-doc """
render_type(Module, DocsOrType, ConfigOrDocs)

Render all types in a module or type documentation.

Renders a list with all types if called as `render_type(Module, Docs, Config)`.

Equivalent to [`render_type(Module, Type, Docs, #{})`](`render_type/4`) if called
as `render_type(Module, Type, Docs)`.
""".
-doc(#{since => <<"OTP 23.0">>}).
-spec render_type(Module, Docs, Config) -> unicode:chardata() when
      Module :: module(),
      Docs :: docs_v1(),
      Config :: config();
                 (Module, Type, Docs) -> Res when
      Module :: module(), Type :: atom(),
      Docs :: docs_v1(),
      Res :: unicode:chardata() | {error, type_missing}.
render_type(Module, D = #docs_v1{}, Config) ->
    render_signature_listing(Module, type, D, Config);
render_type(Module, Type, D = #docs_v1{}) ->
    render_type(Module, Type, D, #{}).

-doc """
render_type(Module, Type, DocsOrArity, ConfigOrDocs)

Render type documentation.

Renders the type documentation if called as `render_type(Module, Type, Docs, Config)`.

Equivalent to [`render_type(Module, Type, Arity, Docs, #{})`](`render_type/4`) if called
as `render_type(Module, Type, Arity, Docs)`.
""".
-doc(#{since => <<"OTP 23.0">>}).
-spec render_type(Module, Type, Docs, Config) -> Res when
      Module :: module(), Type :: atom(),
      Docs :: docs_v1(),
      Config :: config(),
      Res :: unicode:chardata() | {error, type_missing};
                 (Module, Type, Arity, Docs) -> Res when
      Module :: module(), Type :: atom(), Arity :: arity(),
      Docs :: docs_v1(),
      Res :: unicode:chardata() | {error, type_missing}.
render_type(_Module, Type, #docs_v1{ } = D, Config) ->
    render_typecb(_Module, Type, none, D, Config);
render_type(_Module, Type, Arity, #docs_v1{ } = D) ->
    render_typecb(_Module, Type, Arity, D, #{}).

-doc "Render the documentation of a type in a module.".
-doc(#{since => <<"OTP 23.2">>}).
-spec render_type(Module, Type, Arity, Docs, Config) -> Res when
      Module :: module(), Type :: atom(), Arity :: arity(),
      Docs :: docs_v1(),
      Config :: config(),
      Res :: unicode:chardata() | {error, type_missing}.
render_type(_Module, Type, Arity, #docs_v1{ } = D, Config) ->
    render_typecb(_Module, Type, Arity, D, Config).

render_typecb(_Module, Type, Arity, #docs_v1{ } = D, Config) ->
    renderer(Config, {_Module, type, Type, Arity}, D).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% API function for dealing with the callback documentation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-doc false.
-spec get_callback_doc(Module :: module(), Callback :: atom(), Arity :: arity()) ->
          [{{callback,Callback,Arity}, Anno, Signature, chunk_elements(), Metadata}] when
      Callback :: atom(),
      Arity :: arity(),
      Anno :: erl_anno:anno(),
      Signature :: [binary()],
      Metadata :: map().
get_callback_doc(Module, Callback, Arity) ->
    {ok, #docs_v1{ docs = Docs } = D} = code:get_doc(Module),
    Map = fun ({F,A,S,Dc,M}) -> {F,A,S,get_local_doc(F, Dc, D),M} end,
    filtermap_mfa({callback, Callback, Arity}, Map, Docs).

-doc(#{equiv => render_callback(Module, Docs, #{})}).
-doc(#{since => <<"OTP 23.0">>}).
-spec render_callback(Module, Docs) -> unicode:chardata() when
      Module :: module(),
      Docs :: docs_v1().
render_callback(Module, D) ->
    render_callback(Module, D, #{}).

-doc """
render_callback(Module, DocsOrCallback, ConfigOrDocs)

Render all callbacks in a module or callback documentation.

Renders a list with all callbacks if called as `render_callback(Module, Docs, Config)`.

Equivalent to [`render_callback(Module, Callback, Docs, #{})`](`render_callback/4`) if called
as `render_callback(Module, Callback, Docs)`.
""".
-doc(#{since => <<"OTP 23.0">>}).
-spec render_callback(Module, Docs, Config) -> unicode:chardata() when
      Module :: module(),
      Docs :: docs_v1(),
      Config :: config();
                     (Module, Callback, Docs) -> Res when
      Module :: module(), Callback :: atom(),
      Docs :: docs_v1(),
      Res :: unicode:chardata() | {error, callback_missing}.
render_callback(_Module, Callback, #docs_v1{ } = D) ->
    render_callback(_Module, Callback, D, #{});
render_callback(Module, D, Config) ->
    render_signature_listing(Module, callback, D, Config).

-doc """
render_callback(Module, Callback, DocsOrArity, ConfigOrDocs)

Render callback documentation.

Renders the callback documentation if called as `render_callback(Module, Callback, Docs, Config)`.

Equivalent to [`render_callback(Module, Callback, Arity, Docs, #{})`](`render_callback/4`) if called
as `render_callback(Module, Callback, Arity, Docs)`.
""".
-doc(#{since => <<"OTP 23.0">>}).
-spec render_callback(Module, Callback, Docs, Config) -> Res when
      Module :: module(), Callback :: atom(),
      Docs :: docs_v1(),
      Config :: config(),
      Res :: unicode:chardata() | {error, callback_missing};
                     (Module, Callback, Arity, Docs) -> Res when
      Module :: module(), Callback :: atom(), Arity :: arity(),
      Docs :: docs_v1(),
      Res :: unicode:chardata() | {error, callback_missing}.
render_callback(_Module, Callback, Arity, #docs_v1{ } = D) ->
    render_cb(_Module, Callback, Arity, D, #{});
render_callback(_Module, Callback, #docs_v1{ } = D, Config) ->
    render_cb(_Module, Callback, none, D, Config).

-doc "Render the documentation of a callback in a module.".
-doc(#{since => <<"OTP 23.2">>}).
-spec render_callback(Module, Callback, Arity, Docs, Config) -> Res when
      Module :: module(), Callback :: atom(), Arity :: arity(),
      Docs :: docs_v1(),
      Config :: config(),
      Res :: unicode:chardata() | {error, callback_missing}.
render_callback(_Module, Callback, Arity, #docs_v1{ } = D, Config) ->
    render_cb(_Module, Callback, Arity, D, Config).

render_cb(_Module, Type, Arity, #docs_v1{ } = D, Config) ->
    renderer(Config, {_Module, callback, Type, Arity}, D).


%% Get the docs in the correct locale if it exists.
-spec get_local_doc(atom() | tuple() | binary(), Docs, D) -> term() when
    Docs :: map() | none | hiddden,
    D    :: docs_v1().
get_local_doc(MissingMod, Docs, D) when is_atom(MissingMod) ->
    get_local_doc(atom_to_binary(MissingMod), Docs, D);
get_local_doc({F,A}, Docs, D) ->
    get_local_doc(unicode:characters_to_binary(
                    io_lib:format("~tp/~p",[F,A])), Docs, D);
get_local_doc({_Type,F,A}, Docs, D) ->
    get_local_doc({F,A}, Docs, D);
get_local_doc(_Missing, #{ <<"en">> := Docs }, D) ->
    %% English if it exists
    normalize_format(Docs, D);
get_local_doc(_Missing, ModuleDoc, D) when map_size(ModuleDoc) > 0 ->
    %% Otherwise take first alternative found
    normalize_format(maps:get(hd(maps:keys(ModuleDoc)), ModuleDoc), D);
get_local_doc(Missing, hidden, _D) ->
    [{p,[],[<<"The documentation for ">>,Missing,
            <<" is hidden. This probably means that it is internal "
              "and not to be used by other applications.">>]}];
get_local_doc(Missing, None, _D) when None =:= none; None =:= #{} ->
    [{p,[],[<<"There is no documentation for ">>,Missing]}].

normalize_format(Docs, #docs_v1{ format = ?NATIVE_FORMAT }) ->
    normalize(Docs);
normalize_format(Docs, #docs_v1{ format = <<"text/markdown">> }) when is_binary(Docs) ->
    normalize(shell_docs_markdown:parse_md(Docs));
normalize_format(Docs, #docs_v1{ format = <<"text/", _/binary>> }) when is_binary(Docs) ->
    [{pre, [], [Docs]}].

%%% Functions for rendering reference documentation
render_function([], _D, _Config) ->
    {error,function_missing};
render_function(FDocs, D, Config) when is_map(Config) ->
    render_function(FDocs, D, init_config(D, Config));
render_function(FDocs, #docs_v1{ docs = Docs } = D, Config) ->
    GlobalSpecs = extract_type_specs(Config#config.module),
    Grouping =
        lists:foldr(
          fun({_Group,_Anno,_Sig,_Doc,#{ equiv := Group }} = Func, Acc) ->
                  case lists:keytake(Group, 1, Acc) of
                      false -> [{Group, [Func], render_signature(Func, GlobalSpecs)} | Acc];
                      {value, {Group, Members, Sigs}, NewAcc} ->
                          [{Group, [Func | Members], render_signature(Func, GlobalSpecs) ++ Sigs} | NewAcc]
                  end;
             ({Group, _Anno, _Sig, _Doc, _Meta} = Func, Acc) ->
                  [{Group, [Func], render_signature(Func, GlobalSpecs)} | Acc]
          end, [],
          %% We sort only on the group element, so that multiple entries with
          %% the same group do not change order. For example erlang:halt/1.
          lists:sort(fun(A, B) -> element(1, A) =< element(1, B) end, FDocs)),
    lists:map(
      fun({Group, Members, Signatures}) ->
              Docs0 = case lists:search(fun({_,_,_,Doc,_}) ->
                                                Doc =/= #{}
                                        end, Members) of
                          {value, {_,_,_,Doc,_Meta}} -> Doc;
                          false ->
                              case lists:keyfind(Group, 1, Docs) of
                                  false -> none;
                                  {_,_,_,Doc,_} -> Doc
                              end
                      end,
              render_headers_and_docs(
                Signatures, get_local_doc(Group, Docs0, D), D, Config)
      end, Grouping).

%% Render the signature of either function, type, or anything else really.
render_signature({{_Type,_F,_A},_Anno,_Sigs,_Docs,#{ signature := Specs } = Meta}, _ASTSpecs) ->
    lists:map( fun render_ast/1,Specs) ++ [render_meta(Meta)];
render_signature({{Type,F,A},_Anno,Sigs,_Docs,Meta}, Specs) ->
    case maps:find({F, A}, maps:get(Type, Specs, #{})) of
        {ok, Spec} ->
            [render_ast(Spec) | render_meta(Meta)];
        error ->
            lists:map(fun(Sig) -> {h2,[],[<<"  "/utf8,Sig/binary>>]} end, Sigs) ++ [render_meta(Meta)]
    end.

render_ast(AST) ->
    PPSpec = erl_pp:attribute(AST,[{encoding,unicode}]),
    Spec = case AST of
               {_Attribute, _Line, opaque, _} ->
                   %% We do not want show the internals of the opaque type
                   hd(string:split(PPSpec,"::"));
               _ ->
                   PPSpec
           end,
    BinSpec = unicode:characters_to_binary(string:trim(Spec, trailing, "\n")),
    {pre,[],[{strong,[],BinSpec}]}.

render_meta(M) ->
    case render_meta_(M) of
        [] -> [];
        Meta ->
            [[{dl,[],Meta}]]
    end.
render_meta_(#{ since := Vsn } = M) ->
    [{dt,[],<<"Since">>},{dd,[],[unicode:characters_to_binary(Vsn)]}
    | render_meta_(maps:remove(since, M))];
render_meta_(#{ deprecated := Depr } = M) ->
    [{dt,[],<<"Deprecated">>},{dd,[],[unicode:characters_to_binary(Depr)]}
    | render_meta_(maps:remove(deprecated, M))];
render_meta_(_) ->
    [].

render_headers_and_docs(Headers, DocContents, D, Config) ->
    render_headers_and_docs(Headers, DocContents, init_config(D, Config)).
render_headers_and_docs(Headers, DocContents, #config{} = Config) ->
    ["\n",render_docs(
       lists:flatmap(
         fun(Header) ->
                 [{br,[],[]},Header]
         end,Headers), Config),
     "\n",
     render_docs(DocContents, 2, Config)].

%%% Functions for rendering type/callback documentation
render_signature_listing(Module, Type, D, Config) when is_map(Config) ->
    render_signature_listing(Module, Type, D, init_config(D, Config));
render_signature_listing(Module, Type, #docs_v1{ docs = Docs, module_doc = MD } = D, #config{}=Config) ->
    Config0 = config_module(Module, Config),
    Slogan = [{h2,[],[<<"\t",(atom_to_binary(Module))/binary>>]},{br,[],[]}],
    case lists:filter(fun({{T, _, _},_Anno,_Sig,_Doc,_Meta}) ->
                              Type =:= T andalso is_map(MD)
                      end, Docs) of
        [] ->
            render_docs(
              Slogan ++ [<<"There are no ",(atom_to_binary(Type))/binary,"s "
                           "in this module">>], D, Config0);
        Headers ->
            Specs = extract_type_specs(Module),
            Hdr = lists:flatmap(
                    fun(Header) ->
                            [{br,[],[]},render_signature(Header, Specs)]
                    end,Headers),
            render_docs(
              Slogan ++
                  [{p,[],[<<"These ",(atom_to_binary(Type))/binary,"s "
                            "are documented in this module:">>]},
                   {br,[],[]}, Hdr], D, Config0)
    end.

render_typecb_docs([], _C) ->
    {error,type_missing};
render_typecb_docs(TypeCBs, #config{} = C) when is_list(TypeCBs) ->
    [render_typecb_docs(TypeCB, C) || TypeCB <- TypeCBs];
render_typecb_docs({F,_,_Sig,Docs,_Meta} = TypeCB, #config{docs = D, module=Mod} = C) ->
    Specs = extract_type_specs(Mod),
    render_headers_and_docs(render_signature(TypeCB, Specs), get_local_doc(F,Docs,D), C).
render_typecb_docs(Docs, D, Config) ->
    render_typecb_docs(Docs, init_config(D, Config)).

%%% General rendering functions
render_docs(DocContents, #config{} = Config) ->
    render_docs(DocContents, 0, Config).
render_docs(DocContents, D, Config) when is_record(D, docs_v1) ->
    render_docs(DocContents, 0, init_config(D, Config));
render_docs(DocContents, Ind, D = #config{}) when is_integer(Ind) ->
    init_ansi(D),
    try
        {Doc,_} = trimnl(render_docs(DocContents, [], 0, Ind, D)),
        Doc
    after
        clean_ansi()
    end.

init_config(D, Config) when is_map(Config) ->
    DefaultOpts = io:getopts(),
    DefaultEncoding = proplists:get_value(encoding, DefaultOpts, latin1),
    Columns =
        case maps:find(columns, Config) of
            error ->
                get_columns();
            {ok, C} ->
                C
        end,
    #config{ docs = D,
             encoding = maps:get(encoding, Config, DefaultEncoding),
             ansi = maps:get(ansi, Config, undefined),
             columns = Columns,
             module = maps:get(module, Config, undefined)
           };
init_config(D, Config) ->
    Config#config{ docs = D }.

get_columns() ->
    case application:get_env(stdlib, shell_docs_columns) of
        {ok, C} when is_integer(C), C > 0 ->
            C;
        _ ->
            case io:columns() of
                 {ok, C} ->
                     C;
                 _ ->
                     80
             end
    end.

render_docs(Elems,State,Pos,Ind,D) when is_list(Elems) ->
    lists:mapfoldl(fun(Elem,P) ->
                          render_docs(Elem,State,P,Ind,D)
                   end,Pos,Elems);
render_docs(Elem,State,Pos,Ind,D) ->
    render_element(Elem,State,Pos,Ind,D).


%%% The function is the main element rendering function
%%%
%%% Elem: The current element to process
%%% Stack: A stack of element names to see where we are in the dom
%%% Pos: The current print position on the current line
%%% Ind: How much the text should be indented after a newline
%%% Config: The renderer's configuration
%%%
%%% Each element is responsible for putting new lines AFTER itself
%%% The indents are done either by render_words when a newline happens
%%% or when a new element is to be rendered and Pos < Ind.
%%%
%%% Any block elements (i.e. p, ul, li etc) are responsible for trimming
%%% extra new lines. eg. <ul><li><p>content</p></li></ul> should only
%%% have two newlines at the end.
-spec render_element(Elem :: chunk_element(),
                     Stack :: [chunk_element_type()],
                     Pos :: non_neg_integer(),
                     Indent :: non_neg_integer(),
                     Config :: #config{}) ->
          {unicode:chardata(), Pos :: non_neg_integer()}.

render_element({IgnoreMe,_,Content}, State, Pos, Ind,D)
  when IgnoreMe =:= a ->
    render_docs(Content, State, Pos, Ind,D);

%% Catch h* before the padding is done as they reset padding
render_element({h1,_,Content},State,0 = Pos,_Ind,D) ->
    trimnlnl(render_element({code,[],[{strong,[],Content}]}, State, Pos, 0, D));
render_element({h2,_,Content},State,0 = Pos,_Ind,D) ->
    trimnlnl(render_element({strong,[],Content}, State, Pos, 0, D));
render_element({H,_,Content},State,Pos,_Ind,D)
  when Pos =< 2, H =:= h3 orelse H =:= h4 orelse H =:= h5 orelse H =:= h6 ->
    trimnlnl(render_element({code,[],Content}, State, Pos, 2, D));

render_element({pre,_Attr,_Content} = E,State,Pos,Ind,D) when Pos > Ind ->
    %% We pad `pre` with two newlines if the previous section did not indent the region.
    {Docs,NewPos} = render_element(E,State,0,Ind,D),
    {["\n\n",Docs],NewPos};
render_element({Elem,_Attr,_Content} = E,State,Pos,Ind,D) when Pos > Ind, ?IS_BLOCK(Elem) ->
    {Docs,NewPos} = render_element(E,State,0,Ind,D),
    {["\n",Docs],NewPos};
render_element({'div',[{class,What}],Content},State,Pos,Ind,D) ->
    {Docs,_} = render_docs(Content, ['div'|State], 0, Ind+2, D),
    trimnlnl([pad(Ind - Pos),string:titlecase(What),":\n",Docs]);
render_element({blockquote,_Attr,Content},State,_Pos,Ind,D) ->
    trimnlnl(render_docs(Content, ['div'|State], 0, Ind+2, D));
render_element({Tag,_,Content},State,Pos,Ind,D) when Tag =:= p; Tag =:= 'div' ->
    trimnlnl(render_docs(Content, [Tag|State], Pos, Ind, D));

render_element(Elem,State,Pos,Ind,D) when Pos < Ind ->
    {Docs,NewPos} = render_element(Elem,State,Ind,Ind,D),
    {[pad(Ind - Pos), Docs],NewPos};

render_element({code,_,Content},[pre|_]  = State,Pos,Ind,D) ->
    %% When code is within a pre we don't emit any underline
    render_docs(Content, [code|State], Pos, Ind,D);
render_element({code,_,Content},State,Pos,Ind,D) ->
    Underline = sansi(underline),
    {Docs, NewPos} = render_docs(Content, [code|State], Pos, Ind,D),
    {[Underline,Docs,ransi(underline)], NewPos};

render_element({em,Attr,Content},State,Pos,Ind,D) ->
    render_element({i,Attr,Content},State,Pos,Ind,D);
render_element({i,_,Content},State,Pos,Ind,D) ->
    %% Just ignore i as ansi does not have cursive style
    render_docs(Content, State, Pos, Ind,D);

render_element({br,[],[]},_State,Pos,_Ind,_D) ->
    {"",Pos};

render_element({strong,Attr,Content},State,Pos,Ind,D) ->
    render_element({b,Attr,Content},State,Pos,Ind,D);
render_element({b,_,Content},State,Pos,Ind,D) ->
    Bold = sansi(bold),
    {Docs, NewPos} = render_docs(Content, State, Pos, Ind,D),
    {[Bold,Docs,ransi(bold)], NewPos};

render_element({pre,_,Content},State,Pos,Ind,D) ->
    %% For pre we make sure to respect the newlines in pre
    trimnlnl(render_docs(Content, [pre|State], Pos, Ind+2, D));

render_element({ul,[{class,<<"types">>}],Content},State,_Pos,Ind,D) ->
    {Docs, _} = render_docs(Content, [types|State], 0, Ind+2, D),
    trimnlnl(["Types:\n", Docs]);
render_element({li,Attr,Content},[types|_] = State,Pos,Ind,C) ->
    Doc =
        case {proplists:get_value(name, Attr),proplists:get_value(class, Attr)} of
            {undefined,Class} when Class =:= undefined; Class =:= <<"type">> ->
                %% Inline html for types
                render_docs(Content,[type|State],Pos,Ind,C);
            {_,<<"description">>} ->
                %% Inline html for type descriptions
                render_docs(Content,[type|State],Pos,Ind+2,C);
            {Name,_} ->
                %% Try to render from type metadata
                case render_type_signature(binary_to_atom(Name),C) of
                    undefined when Content =:= [] ->
                        %% Failed and no content, emit place-holder
                        {["-type ",Name,"() :: term()."],0};
                    undefined ->
                        %% Failed with metadata, render the content
                        render_docs(Content,[type|State],Pos,Ind,C);
                    Type ->
                        %% Emit the erl_pp typespec
                        {Type,0}
                end
        end,
    trimnl(Doc);
render_element({ul,[],Content},State,Pos,Ind,D) ->
    render_docs(Content, [l|State], Pos, Ind,D);
render_element({ol,[],Content},State,Pos,Ind,D) ->
    %% For now ul and ol does the same thing
    render_docs(Content, [l|State], Pos, Ind,D);
render_element({li,[],Content},[l | _] = State, Pos, Ind,D) ->
    Bullet = get_bullet(State, D#config.encoding),
    BulletLen = string:length(Bullet),
    {Docs, _NewPos} = render_docs(Content, [li | State], Pos + BulletLen,Ind + BulletLen, D),
    trimnlnl([Bullet,Docs]);

render_element({dl,_,Content},State,Pos,Ind,D) ->
    render_docs(Content, [dl|State], Pos, Ind,D);
render_element({dt,Attr,Content},[dl | _] = State,Pos,Ind,D) ->
    Since = case Attr of
                [{since, Vsn}] ->
                    ["     (since ",unicode:characters_to_list(Vsn),$)];
                [] ->
                    []
             end,
    Underline = sansi(underline),
    {Docs, _NewPos} = render_docs(Content, [li | State], Pos, Ind, D),
    {[Underline,Docs,ransi(underline),$:,Since,$\n], 0};
render_element({dd,_,Content},[dl | _] = State,Pos,Ind,D) ->
    trimnlnl(render_docs(Content, [li | State], Pos, Ind + 2, D));

render_element(B, State, Pos, Ind, D) when is_binary(B) ->
    case lists:member(pre,State) of
        true ->
            Pre = string:replace(B,"\n",[nlpad(Ind)],all),
            {Pre, Pos + lastline(Pre)};
        _ ->
            render_words(split_to_words(B),State,Pos,Ind,[[]],D)
    end;

render_element({Tag,Attr,Content}, State, Pos, Ind,D) ->
    case lists:member(Tag,?ALL_ELEMENTS) of
        true ->
            throw({unhandled_element,Tag,Attr,Content});
        false ->
            %% We ignore tags that we do not care about
            ok
    end,
    render_docs(Content, State, Pos, Ind,D).

render_words(Words,[_,types|State],Pos,Ind,Acc,D) ->
    %% When we render words and are in the types->type state we indent
    %% the extra lines two additional spaces to make it look nice
    render_words(Words,State,Pos,Ind+2,Acc,D);
render_words([UnicodeWord|T],State,Pos,Ind,Acc,#config{ columns = Cols } = D)
  when is_binary(UnicodeWord) ->
    Word = translate(UnicodeWord, D),
    WordLength = string:length(Word),
    NewPos = WordLength + Pos,
    %% We do not want to add a newline if this word is only a punctuation
    IsPunct = re:run(Word,"^\\W$",[unicode]) =/= nomatch,

    if
        NewPos > (Cols - 10 - Ind), Word =/= <<>>, not IsPunct ->
            %% Word does not fit, time to add a newline and also pad to Indent level
            render_words(T,State,WordLength+Ind+1,Ind,[[[nlpad(Ind), Word]]|Acc],D);
        true ->
            %% Word does fit on line
            [Line | LineAcc] = Acc,
            %% Add + 1 to length for space
            NewPosSpc = NewPos+1,
            render_words(T,State,NewPosSpc,Ind,[[Word|Line]|LineAcc],D)
    end;
render_words([],_State,Pos,_Ind,Acc,_D) ->
    Lines = lists:map(fun(RevLine) ->
                            Line = lists:reverse(RevLine),
                            lists:join($ ,Line)
                      end,lists:reverse(Acc)),
    {iolist_to_binary(Lines), Pos}.

%% If the encoding is not unicode, we translate all nbsp to sp
translate(UnicodeWord, #config{ encoding = unicode }) ->
    UnicodeWord;
translate(UnicodeWord, #config{ encoding = latin1 }) ->
    string:replace(UnicodeWord, [160], " ", all).

render_type_signature(Name, #config{ docs = #docs_v1{ metadata = #{ types := AllTypes }}}) ->
    case [Type || Type = {TName,_} <- maps:keys(AllTypes), TName =:= Name] of
        [] ->
            undefined;
        Types ->
            [erl_pp:attribute(maps:get(Type, AllTypes)) || Type <- Types]
    end.

%% Pad N spaces (and possibly pre-prend newline), disabling any ansi formatting while doing so.
pad(N) ->
    pad(N,"").
nlpad(N) ->
    %% It is important that we disable the ansi code before the new-line as otherwise the
    %% ansi decoration may be enabled when c:paged_output tries to ask if more content
    %% should be displayed.
    pad(N,"\n").
pad(N, Extra) ->
    Pad = lists:duplicate(N," "),
    case ansi() of
        undefined ->
            [Extra, Pad];
        Ansi ->
            ["\033[0m",Extra,Pad,Ansi]
    end.

get_bullet(_State,latin1) ->
    <<" * ">>;
get_bullet(State,unicode) ->
    %% Fancy bullet point logic!
    case length([l || l <- State]) of
        Level when Level > 4 ->
            get_bullet(State, latin1);
        Level ->
            lists:nth(Level,
                      [<<" • "/utf8>>,<<" ￮ "/utf8>>,
                       <<" ◼ "/utf8>>,<<" ◻ "/utf8>>])
    end.

%% Look for the length of the last line of a string
lastline(Str) ->
    LastStr = case string:find(Str,"\n",trailing) of
                  nomatch ->
                      Str;
                  Match ->
                      tl(string:next_codepoint(Match))
              end,
    string:length(LastStr).

split_to_words(B) ->
    binary:split(B,[<<" ">>],[global]).

%% These functions make sure that we trim extra newlines added
%% by the renderer. For example if we do <li><p></p></li>
%% that would add 4 \n at after the last </li>. This is trimmed
%% here to only be 2 \n
trimnlnl({Chars, _Pos}) ->
    nl(nl(string:trim(Chars, trailing, "\n")));
trimnlnl(Chars) ->
    nl(nl(string:trim(Chars, trailing, "\n"))).
trimnl({Chars, _Pos}) ->
    nl(string:trim(Chars, trailing, "\n")).
nl({Chars, _Pos}) ->
    nl(Chars);
nl(Chars) ->
    {[Chars,"\n"],0}.

%% We keep the current ansi state in the pdict so that we know
%% what to disable and enable when doing padding
init_ansi(#config{ ansi = undefined, io_opts = Opts }) ->
    %% We use this as our heuristic to see if we should print ansi or not
    case {application:get_env(kernel, shell_docs_ansi),
          proplists:get_value(terminal, Opts, false),
          proplists:is_defined(echo, Opts) andalso
          proplists:is_defined(expand_fun, Opts)} of
        {{ok,false}, _, _} ->
            put(ansi, noansi);
        {{ok,true}, _, _} ->
            put(ansi, []);
        {_, true, _} ->
            put(ansi, []);
        {_, _, true} ->
            put(ansi, []);
        {_, _, false} ->
            put(ansi, noansi)
    end;
init_ansi(#config{ ansi = true }) ->
    put(ansi, []);
init_ansi(#config{ ansi = false }) ->
    put(ansi, noansi).



clean_ansi() ->
    case get(ansi) of
        [] -> erase(ansi);
        noansi -> erase(ansi)
    end,
    ok.

%% Set ansi
sansi(Type) -> sansi(Type, get(ansi)).
sansi(_Type, noansi) ->
    [];
sansi(Type, Curr) ->
    put(ansi,[Type | Curr]),
    ansi(get(ansi)).

%% Clear ansi
ransi(Type) -> ransi(Type, get(ansi)).
ransi(_Type, noansi) ->
    [];
ransi(Type, Curr) ->
    put(ansi,proplists:delete(Type,Curr)),
    case ansi(get(ansi)) of
        undefined ->
            "\033[0m";
        Ansi ->
            Ansi
    end.

ansi() -> ansi(get(ansi)).
ansi(noansi) -> undefined;
ansi(Curr) ->
    case lists:usort(Curr) of
        [] ->
            undefined;
        [bold] ->
            "\033[;1m";
        [underline] ->
            "\033[;;4m";
        [bold,underline] ->
            "\033[;1;4m"
    end.

filtermap_mfa({MetaKind, Function, none}, Map, Docs) ->
  [Map(D) || {{MK, F, _},_Anno,_Sig,_Doc,_Meta}=D <- Docs, MK =:= MetaKind andalso F =:= Function];
filtermap_mfa({MetaKind, Function, Arity}, Map, Docs) ->
  [Map(D) || {{MK, F, A},_Anno,_Sig,_Doc,_Meta}=D <- Docs, MK =:= MetaKind andalso F =:= Function andalso Arity =:= A].


%%
%% This function is necessary for a single case.
%% shell_docs_SUITE:render_smoke is 40 seconds faster if we use this one,
%% instead of using a filermap_mfa(_, IdentityFunction, Docs) where
%% IdentityFunction = fun(X) -> X end.
%% Removes one more pointer.
%%
filter_mfa({MetaKind, Function, none}, Docs) ->
  [D || {{MK, F, _},_Anno,_Sig,_Doc,_Meta}=D <- Docs, MK =:= MetaKind andalso F =:= Function];
filter_mfa({MetaKind, Function, Arity}, Docs) ->
  [D || {{MK, F, A},_Anno,_Sig,_Doc,_Meta}=D <- Docs, MK =:= MetaKind andalso F =:= Function andalso Arity =:= A].
