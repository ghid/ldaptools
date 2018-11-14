; ahk: x86
class GroupInfo
{
	static RC_OK             := -1
	     , RC_MISSING_ARG    := -2
	     , RC_INVALID_ARGS   := -3
		 , RC_CYCLE_DETECTED := -4
		 , RC_CN_NOT_FOUND   := -5
		 , RC_CN_AMBIGOUS    := -6

	static options := GroupInfo.set_defaults()

	static dn := ""
	static cn := ""
	static filter := "*"
	static member_list := []
	static scanned_group := []
	static out_file_name := ""
	static out_h := 0
	static group_list := []
	static group_filter := "groupOfNames"

	static LDAP_CONN := 0

	set_defaults()
	{
		return { append: ""
			, base_dn: ""
			, color: false
			, count: false
			, count_only: false
			, env_dummy: false
			, group: ""
			, help: false
			, host: "localhost"
			, ibm_all_groups: false
			, ibm_nested_group: false
			, ignore_case: -1
			, lower: false
			, max_nested_lv: 32
			, output: ""
			, port: 389
			, quiet: false
			, refs: false
			, regex: false
			, result_only: false
			, short: false
			, sort: false
			, upper: false
			, version: false }
	}

	cli()
	{
		_log := new Logger("class." A_ThisFunc)

		op := new OptParser("gi [-a <filename> | -o <filename>] [options] <cn> [filter]",
			, "GI_OPTIONS")
		op.Add(new OptParser.String("a", "append", GroupInfo.options, "append", "file-name"
			,"Append result to existing file"))
		op.Add(new OptParser.String("o", "", GroupInfo.options, "output", "file-name"
			, "Write result to file"))
		op.Add(new OptParser.Group("`nOptions"))
		op.Add(new OptParser.Boolean("1", "short", GroupInfo.options, "short"
			, "Display group names instead of the DN"))
		op.Add(new OptParser.Boolean("c", "count", GroupInfo.options, "count"
			, "Display number of hits"))
		op.Add(new OptParser.Boolean("C", "count-only", GroupInfo.options, "count_only"
			, "Return the number of hits as exit code; no other output"))
		op.Add(new OptParser.Boolean("e", "regex", GroupInfo.options, "regex"
			, "Use a regular expression to filter the result set "
			. "(see also http://ahkscript.org/docs/misc/RegEx-QuickRef.htm)"))
		op.Add(new OptParser.String("h", "host", GroupInfo.options, "host", "host-name"
			, "Hostname of the LDAP server (default=" GroupInfo.options.host ")"
			,, GroupInfo.options.host, GroupInfo.options.host))
		op.Add(new OptParser.String("p", "port", GroupInfo.options, "port", "portnum"
			, "Port number of the LDAP server (default=" GroupInfo.options.port ")"
			,, GroupInfo.options.port, GroupInfo.options.port))
		op.Add(new OptParser.String("b", "base-dn", GroupInfo.options, "base_dn", "basedn"
			, "Base DN to start the search"
			,, GroupInfo.options.base_dn, GroupInfo.options.base_dn))
		op.Add(new OptParser.Callback("g", "group", GroupInfo.options, "group"
			, "cb_Numeric", "number"
			, "Return the group of regex evaluation as result (implies -e)", OptParser.OPT_ARG))
		op.Add(new OptParser.Boolean("i", "ignore-case", GroupInfo.options, "ignore_case"
			, "Ignore case when filtering results"
			, OptParser.OPT_NEG, GroupInfo.options.ignore_case, GroupInfo.options.ignore_case))
		op.Add(new OptParser.Boolean("l", "lower", GroupInfo.options, "lower"
			, "Display result in lower case characters"))
		op.Add(new OptParser.Boolean("u", "upper", GroupInfo.options, "upper"
			, "Display result in upper case characters"))
		op.Add(new OptParser.Boolean("r", "refs", GroupInfo.options, "refs"
			, "Display group relations"))
		op.Add(new OptParser.Boolean("s", "sort", GroupInfo.options, "sort", "Sort result"))
		op.Add(new OptParser.Boolean(0, "color", GroupInfo.options, "color"
			, "Colored output (deactivated by default if -a or -o option is set)"
			, OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE, -1, true))
		op.Add(new OptParser.Boolean("R", "result-only", GroupInfo.options, "result_only"
			, "Suppress any other output than the found groups"))
		op.Add(new OptParser.Boolean(0, "ibm-nested-group", GroupInfo.options, "ibm_nested_group"
			, "Only show groups which implement objectclass ibm-nestedGroup"))
		op.Add(new OptParser.Boolean(0, "ibm-all-groups", GroupInfo.options, "ibm_all_groups"
			, "Use 'ibm_allgroups' to retrieve data"))
		op.Add(new OptParser.String(0, "max-nested-level", GroupInfo.options, "max_nested_lv", "n"
			, "Defines, which recursion depth terminates the process (default=32)"
			,, GroupInfo.options.max_nested_lv, GroupInfo.options.max_nested_lv))
		op.Add(new OptParser.Boolean(0, "env", GroupInfo.options, "env_dummy"
			, "Ignore environment variable GI_OPTIONS", OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE))
		op.Add(new OptParser.Boolean("q", "quiet", GroupInfo.options, "quiet"
			, "Suppress output of results"))
		op.Add(new OptParser.Boolean(0, "version", GroupInfo.options, "version"
			, "Print version info"))
		op.Add(new OptParser.Boolean(0, "help", GroupInfo.options, "help"
			, "Print help", OptParser.OPT_HIDDEN))

		return _log.Exit(op)
	}

	; TODO: Refactor this run method!
	run(in_args)
	{
		_log := new Logger("class." A_ThisFunc)

		if (_log.Logs(Logger.Input))
		{
		    _log.Input("in_args", in_args)
			if (_log.Logs(Logger.Finest))
			{
				_log.Finest("in_args:`n" LoggingHelper.Dump(in_args))
			}
		}

		try
		{
			rc := GroupInfo.RC_OK
			op := GroupInfo.cli()
			args := op.Parse(in_args)
			if (_log.Logs(Logger.Finest))
			{
				_log.Finest("GroupInfo.options:`n" LoggingHelper.Dump(GroupInfo.options))
			}
			
			if (GroupInfo.options.help) {
				Ansi.WriteLine(op.Usage())
				return _log.Exit("")
			}
			else if (GroupInfo.options.version)
			{
				Ansi.WriteLine(G_VERSION_INFO.NAME "/"
					. G_VERSION_INFO.ARCH "-b" G_VERSION_INFO.BUILD)
				return _log.Exit("")
			}
			else if (args.MaxIndex() < 1)
			{
				throw Exception("error: Missing argument",, GroupInfo.RC_MISSING_ARG)
			}
			else if (GroupInfo.options.output && GroupInfo.options.append)
			{
				throw Exception("error: Options '-o' and '-a' cannot be used together",
					, GroupInfo.RC_INVALID_ARGS)
			}
			else if (GroupInfo.options.upper && GroupInfo.options.lower)
			{
				throw Exception("error: Options '-l' and '-u' cannot be used together",
					, GroupInfo.RC_INVALID_ARGS)
			}
			else if (GroupInfo.options.ibm_all_groups && GroupInfo.options.refs)
			{
				throw Exception("error: Options '-r' and '--ibm-all-groups' "
					. "cannot be used together" ,, GroupInfo.RC_INVALID_ARGS)
			}
			else if (GroupInfo.options.ibm_all_groups && GroupInfo.options.ibm_nested_group) {
				throw Exception("error: Options '--ibm-nested-group' and '--ibm-all-groups' "
					. "cannot be used together",, GroupInfo.RC_INVALID_ARGS)
			}

			if (GroupInfo.group_list.MaxIndex() <> "")
			{
				GroupInfo.options.group := true
				if (!GroupInfo.options.regex)
				{
					GroupInfo.options.regex := true
					if (_log.Logs(Logger.Info))
					{
						_log.Info("Option -g implies -e")
						_log.Finest("GroupInfo.options.regex", GroupInfo.options.regex)
					}
				}
			}

			if (GroupInfo.options.ibm_nested_group)
			{
				GroupInfo.group_filter := "ibm-nestedGroup"
			}
			if (_log.Logs(Logger.Finest))
			{
				_log.Finest("GroupInfo.group_filter", GroupInfo.group_filter)
			}

			if (GroupInfo.options.regex) {
				GroupInfo.filter := "(.*)"
			}

			GroupInfo.cn := args[1]
			if (args.MaxIndex() = 2)
			{
				GroupInfo.filter := args[2]
			}
			if (_log.Logs(Logger.Finest))
			{
				_log.Finest("GroupInfo.cn", GroupInfo.cn)
				_log.Finest("GroupInfo.filter", GroupInfo.filter)
			}

			if (!GroupInfo.options.count_only && !GroupInfo.options.result_only)
			{
				Ansi.WriteLine(GroupInfo.format_output(dn, ""), true)
				Ansi.Write("Connecting to " GroupInfo.options.host
					. ":" GroupInfo.options.port " ... ")
			}

			rc := GroupInfo.main()
		}
		catch e
		{
			_log.Fatal(e.message)
			Ansi.WriteLine(e.message)
			Ansi.WriteLine(op.Usage())
		}
		finally
		{
			_log.Info("Executing finally block")
			if (GroupInfo.LDAP_CONN)
			{
				GroupInfo.LDAP_CONN.Unbind()
			}
			if (GroupInfo.out_h)
			{
				GroupInfo.out_h.Close()
			}
		}

		return _log.Exit(rc)
	}

	main()
	{
		_log := new Logger("class." A_ThisFunc)

		if (_log.Logs(Logger.Finest))
		{
			_log.Finest("GroupInfo.options:`n" LoggingHelper.Dump(GroupInfo.options))
		}

		if (GroupInfo.options.sort
			|| GroupInfo.options.output
			|| GroupInfo.options.append)
		{
			GroupInfo.out_h := FileOpen(A_Temp "\__gi__.dat", "w`n")
			if ((GroupInfo.options.output || GroupInfo.options.append)
				&& GroupInfo.options.color <> true)
			{
				GroupInfo.options.color := false
				if (_log.Logs(Logger.Warning))
				{
					_log.Warning("option.color has been set to false because of file output"
						, GroupInfo.options.color)
				}
			}
		}

		if (GroupInfo.options.ibm_nested_group) {
			GroupInfo.group_filter := "ibm-nestedGroup"
			if (_log.Logs(Logger.Finest))
			{
				_log.Finest("GroupInfo.group_filter", GroupInfo.group_filter)
			}
		}

		GroupInfo.LDAP_CONN := new Ldap(GroupInfo.options.host, GroupInfo.options.port)
		GroupInfo.LDAP_CONN.Connect()
		if ( !GroupInfo.options.count_only && !GroupInfo.options.result_only)
		{
			Ansi.WriteLine("Ok.")
		}

		dn := GroupInfo.ldap_get_dn("(cn=" GroupInfo.cn ")")
		if (_log.Logs(Logger.Finest))
		{
			_log.Finest("dn", dn)
		}
		if (!GroupInfo.options.count_only && !GroupInfo.options.result_only)
		{
			Ansi.WriteLine(GroupInfo.format_output(dn, ""), true)
		}

		if (!GroupInfo.options.ibm_all_groups) {
			n := GroupInfo.ldap_get_group_list(dn)	
		} else {
			n := GroupInfo.ldap_get_all_group_list(GroupInfo.cn)
		}

		; Handle sort and/or output options; ---------------------------------
		if (GroupInfo.out_h)
		{
			GroupInfo.out_h.Close()
		}
		if (_log.Logs(Logger.Finest))
		{
			_log.Finest("GroupInfo.out_h", GroupInfo.out_h)
		}
		content := ""
		if (GroupInfo.out_h) {
			h_gi := FileOpen(A_Temp "\__gi__.dat", "r`n")
			if (_log.Logs(Logger.Finest))
			{
				_log.Finest("h_gi", h_gi)
				_log.Finest("h_gi.Length", h_gi.Length)
			}
			content := h_gi.Read(h_gi.Length)
			h_gi.Close()
			; FileRead content, %A_Temp%\__gi__.dat
			if (GroupInfo.options.sort)
			{
				Sort content
			}
			FileDelete %A_Temp%\__gi__.dat
		}

		if (GroupInfo.options.append)
		{
			file_name := GroupInfo.options.append
		}
		else if (GroupInfo.options.output)
		{
			file_name := GroupInfo.options.output
			if (FileExist(file_name))
			{
				FileDelete %file_name%
			}
		}
		else
		{
			file_name := "*"
		}
		if (_log.Logs(Logger.Info))
		{
			_log.Info("file_name", file_name)
		}
		if (file_name = "*")
		{
			Ansi.Write(content)
		}
		else
		{
			FileAppend %content%, %file_name%
		}
		content := ""

		if (GroupInfo.options.count)
		{
			Ansi.WriteLine("`n" n " Hit(s)")
		}

		return _log.Exit(n)
	}

	format_output(text, ref)
	{
		_log := new Logger("class." A_ThisFunc)
		
		if (_log.Logs(Logger.Input))
		{
			_log.Input("text", text)
			_log.Input("ref", ref)
		}

		if (GroupInfo.options.refs)
		{
			if (GroupInfo.options.short)
			{
				if (RegExMatch(ref, "^.*?=(.*?),.*$", $))
				{
					ref := $1
				}
			}
		}
		else
		{
			ref := ""
		}
		if (GroupInfo.options.short)
		{
			if (RegExMatch(text, "^.*?=(.*?),.*$", $))
			{
				text := $1	
			}
		}
		if (GroupInfo.options.upper)
		{
			text := text.Upper()
			ref := ref.Upper()
		}
		else if (GroupInfo.options.lower)
		{
			text := text.Lower()
			ref := ref.Lower()
		}

		if (GroupInfo.options.color) {
			text := RegExReplace(text, "(?P<attr>\w+=)"
				, Ansi.SetGraphic(Ansi.FOREGROUND_GREEN, Ansi.ATTR_BOLD)
				. "${attr}"
				. Ansi.SetGraphic(Ansi.ATTR_OFF))
			if (GroupInfo.options.refs && ref <> "")
			{
				ref := Ansi.SetGraphic(Ansi.FOREGROUND_RED, Ansi.ATTR_BOLD)
					. "  <-(" RegExReplace(ref, "(?P<attr>\w+=)"
					, Ansi.SetGraphic(Ansi.FOREGROUND_GREEN, Ansi.ATTR_BOLD)
					. "${attr}"
					. Ansi.SetGraphic(Ansi.ATTR_OFF))
					. Ansi.SetGraphic(Ansi.FOREGROUND_RED, Ansi.ATTR_BOLD)
					. ")" Ansi.SetGraphic(Ansi.ATTR_OFF)
			}
		}
		else
		{
			if (GroupInfo.options.refs)
			{
				ref := "  <-(" ref ")"
			}
		}

		return _log.Exit(text ref)
	}

	output(text)
	{
		_log := new Logger("class." A_ThisFunc)

		if (_log.Logs(Logger.Input))
		{
			_log.Input("text", text)
		}

		res := true
		try
		{
			if (_log.Logs(Logger.Finest))
			{
				_log.Finest("GroupInfo.filter", GroupInfo.filter)
			}

			if (!GroupInfo.options.quiet
				&& res := Ansi.PlainStr(text).Filter(GroupInfo.filter
					, GroupInfo.options.regex
					, (GroupInfo.options.ignore_case = true ? true : false)
					, false
					, match := ""))
			{
				if (_log.Logs(Logger.Finest))
				{
					_log.Finest("GroupInfo.group_list.MaxIndex())"
						, GroupInfo.group_list.MaxIndex())
					_log.Finest("match:`n" LoggingHelper.Dump(match))
					_log.Finest("GroupInfo.out_h", GroupInfo.out_h)
				}

				if (GroupInfo.group_list.MaxIndex() <> "")
				{
					text := ""
					loop % match.Count 
					{
						text .= match[GroupInfo.group_list[A_Index]]	
					}
				}
				if (GroupInfo.out_h)
				{
					GroupInfo.out_h.WriteLine(((!GroupInfo.options.output
						&& !GroupInfo.options.append
						&& !GroupInfo.options.result_only)
						? "   " : "") text)
				}
				else if (!GroupInfo.options.count_only)
				{
					Ansi.WriteLine((!GroupInfo.options.result_only ? "   ":"") text, true)
				}
			}
		}
		catch _ex
		{
			if (_log.Logs(Logger.Severe))
			{
				_log.Severe(_ex.Message)
			}
			throw _log.Exit(_ex)
			res := false
		}
		
		return _log.Exit(res)
	}
	
	ldap_get_group_list(memberdn) {
		_log := new Logger("class." A_ThisFunc)

		static n := 0
		static l := 0
		static group_list := []
		
		if (_log.Logs(Logger.Input))
		{
			_log.Input("memberdn", memberdn)
		}

		if (_log.Logs(Logger.Finest))
		{
			_log.Finest("l", l)
		}

		if (!GroupInfo.LDAP_CONN.Search(sr, GroupInfo.options.base_dn
			, "(&(objectclass=" GroupInfo.group_filter ")(member=" memberdn "))")
			= Ldap.LDAP_SUCCESS)
		{
			throw _log.Exit(Exception(Ldap.Err2String(GroupInfo.LDAP_CONN.GetLastError())))
		}

		if ((iCount := GroupInfo.LDAP_CONN.CountEntries(sr)) < 0)
		{
			throw _log.Exit("error: " Exception(Ldap.Err2String(GroupInfo.LDAP_CONN.GetLastError())))
		}

		if (_log.Logs(Logger.Finest))
		{
			_log.Finest("iCount", iCount)
		}
		loop %iCount%
		{
			if (A_Index = 1)
			{
				member := GroupInfo.LDAP_CONN.FirstEntry(sr)
			}
			else
			{
				member := GroupInfo.LDAP_CONN.NextEntry(member)
			}
			if (member)
			{
				if (!(dn := GroupInfo.LDAP_CONN.GetDn(member)))
				{
					throw _log.Exit(Exception(Ldap.Err2String(GroupInfo.LDAP_CONN.GetLastError())))
				}

				if (_log.Logs(Logger.Finest))
				{
					_log.Finest("A_Index", A_Index)
					_log.Finest("member", member)
					_log.Finest("dn", dn)
				}
				if (_log.Logs(Logger.Finest))
				{
					_log.Finest("group_list[dn]", group_list[dn])
				}
				if (group_list[dn] = "" || GroupInfo.options.refs)
				{
					if (GroupInfo.output(GroupInfo.format_output(dn, memberdn)))
					{
						n++
					}
					group_list[dn] := 1
				}
				l++
				if (l > GroupInfo.options.max_nested_lv)
				{
					_log.Finest("dn", dn)
					_log.Finest("memberdn", memberdn)
					throw _log.Exit(Exception("error: Cyclic reference detected: `n`t"
						. dn "`n`t<- " memberdn,, RC_CYCLE_DETECTED))
				}
				GroupInfo.ldap_get_group_list(dn)
				l--
			}
		}
		
		return _log.Exit(n)
	}

	ldap_get_dn(ldapFilter) {
		_log := new Logger("class." A_ThisFunc)
		
		if (_log.Logs(Logger.Input))
		{
			_log.Input("ldapFilter", ldapFilter)
		}

		if (!GroupInfo.LDAP_CONN.Search(sr, GroupInfo.options.base_dn, ldapFilter)
			= Ldap.LDAP_SUCCESS)
		{
			throw _log.Exit(Exception(Ldap.Err2String(GroupInfo.LDAP_CONN.GetLastError())))
		}

		if ((iCount := GroupInfo.LDAP_CONN.CountEntries(sr)) < 0)
		{
			throw _log.Exit("error: " Exception(Ldap.Err2String(GroupInfo.LDAP_CONN.GetLastError())))
		}

		if (_log.Logs(Logger.Finest))
		{
			_log.Finest("iCount", iCount)
		}
		if (iCount = 0)
		{
			throw _log.Exit(Exception("error: cn not found """ ldapFilter """"
				,, RC_CN_NOT_FOUND))
		}
		else if (iCount > 1)
		{
			throw _log.Exit(Exception("error: cn is ambigous (" iCount ") """ ldapFilter """"
				,, RC_CN_AMBIGOUS))
		}
		entry := GroupInfo.LDAP_CONN.FirstEntry(sr)

		return _log.Exit(GroupInfo.LDAP_CONN.GetDn(entry))
	}

	ldap_get_all_group_list(cn) {
		_log := new Logger("class." A_ThisFunc)

		static n := 0
		static group_list := []
		
		if (_log.Logs(Logger.Input))
		{
			_log.Input("cn", cn)
		}

		if (!GroupInfo.LDAP_CONN.Search(sr, GroupInfo.options.base_dn
			, "(cn=" cn ")",, ["ibm-allgroups"]) = Ldap.LDAP_SUCCESS)
		{
			throw _log.Exit(Exception("error" Ldap.Err2String(GroupInfo.LDAP_CONN.GetLastError())))
		}

		if ((iCount := GroupInfo.LDAP_CONN.CountEntries(sr)) < 0)
		{
			throw _log.Exit("error: " Ldap.Err2String(GroupInfo.LDAP_CONN.GetLastError()))
		}

		if (_log.Logs(Logger.Finest))
		{
			_log.Finest("iCount", iCount)
		}
		loop %iCount%
		{
			if (A_Index = 1)
			{
				member := GroupInfo.LDAP_CONN.FirstEntry(sr)
			}
			else
			{
				member := GroupInfo.LDAP_CONN.NextEntry(member)
			}
			groupAttr := GroupInfo.LDAP_CONN.FirstAttribute(member)
			values := GroupInfo.LDAP_CONN.GetValues(member, groupAttr)
			group_list := System.PtrListToStrArray(values)
			if (_log.Logs(Logger.Finest))
			{
				_log.Finest("A_Index", A_Index)
				_log.Finest("member", member)
				_log.Finest("groupAttr", groupAttr)
				_log.Finest("group_list" LoggingHelper.Dump(group_list))
			}
			n := group_list.MaxIndex()
			if (_log.Logs(Logger.Finest))
			{
				_log.Finest("n", n)
			}
			loop %n%
			{
				GroupInfo.output(GroupInfo.format_output(group_list[A_Index], ""))
			}
		}
		
		return _log.Exit(n)
	}
}

cb_Numeric(number, no_opt = "")
{
	_log := new Logger("app.gi." A_ThisFunc)
	
	if (_log.Logs(Logger.Input))
	{
		_log.Input("number", number)
		_log.Input("no_opt", no_opt)
	}

	GroupInfo.group_list.Push(number)

	if (_log.Logs(Logger.Finest))
	{
		_log.Finest("GroupInfo.group_list:`n" LoggingHelper.Dump(GroupInfo.group_list))
	}
	
	return _log.Exit(GroupInfo.group_list.MaxIndex())
}

#NoEnv												; NOTEST-BEGIN
#MaxHotkeysPerInterval 99000000
#HotkeyInterval 99000000
#KeyHistory 0
ListLines Off
Process, Priority, , H ;if unstable, comment or remove this line
SetBatchLines, -1
SetKeyDelay, -1, -1
SetMouseDelay, -1
SetDefaultMouseSpeed, 0
SetWinDelay, -1
SetControlDelay, -1
SendMode Input

#Include <logging>
#Include <system>
#Include <optparser>
#Include <ansi>
#Include <string>
#Include *i %A_ScriptDir%\gi.versioninfo
#Include <ldap>

Main:
_main := new Logger("app.gi.main")
exitapp _main.Exit(GroupInfo.run(System.vArgs))		; NOTEST-END
; vim:tw=0:ts=4:sts=4:sw=4:noet:ft=autohotkey:bomb
