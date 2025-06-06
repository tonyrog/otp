%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 2023-2025. All Rights Reserved.
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

-module(call_purged_fun).

-export([make_fun/1, make_fun2/0, dummy/1]).

make_fun(A) ->
    fun(X) -> A + X end.

make_fun2() ->
    fun (F1,F2) ->
	    F1(),
	    F2()
    end.

%% Dummy function that ensures the module MD5 is different from the alpha
%% version, keeping us from inheriting its fun entries.
dummy(I) ->
    I.
