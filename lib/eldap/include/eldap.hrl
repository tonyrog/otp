%% SPDX-License-Identifier: MIT
%% SPDX-FileCopyrightText: 2010 Torbjorn Tornkvist <tobbe@tornkvist.org>

-ifndef( _ELDAP_HRL ).
-define( _ELDAP_HRL , 1 ).

%%%
%%% Search input parameters
%%%
-record(eldap_search, {
	  base = [],             % Baseobject
	  filter = [],           % Search conditions
	  size_limit = 0,        % Setting default size limit to 0 makes it unlimited
	  scope=wholeSubtree,    % Search scope
	  deref=derefAlways,     % Dereference
	  attributes = [],       % Attributes to be returned
	  types_only = false,    % Return types+values or types
	  timeout = 0            % Timelimit for search
	 }).

%%%
%%% Returned search result
%%%
-record(eldap_search_result, {
	  entries = [],          % List of #eldap_entry{} records
	  referrals = [],        % List of referrals
	  controls = []          % List of controls
	  }).

%%%
%%% LDAP entry
%%%
-record(eldap_entry, {
	  object_name = "",      % The DN for the entry
	  attributes = []        % List of {Attribute, Value} pairs
	 }).

-endif.
