; ahk: x86
; ahk: console
class GroupUser {

	static RC_OK             := -1
		 , RC_MISSING_ARG    := -2
		 , RC_INVALID_ARGS   := -3
		 , RC_CYCLE_DETECTED := -4
		 , RC_CN_NOT_FOUND   := -5
		 , RC_CN_AMBIGOUS    := -6

	static options := GroupUser.set_defaults()

	static group_filter := "groupOfNames"
	static out_h := 0
	static out_file := ""
    static cn := ""
    static dn := ""
    static filter := "*"

	set_defaults() {
		return { count: ""
			, append: ""
			, color: false
			, count_only: false
			, help: false
			, host: "localhost"
			, ibm_nested_group: false
			, ignore_case: -1
			, invert_match: false
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

	format_output(text, ref)
	{
		_log := new Logger("app.gu." A_ThisFunc)
		
		if (_log.Logs(Logger.Input))
		{
			_log.Input("text", text)
			_log.Input("ref", ref)
		}

		if (GroupUser.options.refs)
		{
			if (GroupUser.options.short)
			{
				if (RegExMatch(ref, "^.*?=\s*(.*?)\s*,.*$", $))
				{
					ref := $1
				}
			}
		}
		else
		{
			ref := ""
		}
		if (GroupUser.options.short)
		{
			if (RegExMatch(text, "^.*?=\s*(.*?)\s*,.*$", $))
			{
				text := $1	
			}
		}
		if (GroupUser.options.upper)
		{
			text := text.Upper()
			ref := ref.Upper()
		}
		else if (GroupUser.options.lower)
		{
			text := text.Lower()
			ref := ref.Lower()
		}

		if (GroupUser.options.color)
		{
			text := RegExReplace(text, "(?P<attr>\w+=)"
				, Ansi.SetGraphic(Ansi.FOREGROUND_GREEN, Ansi.ATTR_BOLD)
				. "${attr}"
				. Ansi.SetGraphic(Ansi.ATTR_OFF))
			if (GroupUser.options.refs && ref <> "")
			{
				ref := Ansi.SetGraphic(Ansi.FOREGROUND_RED, Ansi.ATTR_BOLD)
					. "  <-(" RegExReplace(ref, "(?P<attr>\w+=)"
					, Ansi.SetGraphic(Ansi.FOREGROUND_GREEN, Ansi.ATTR_BOLD)
					. "${attr}"
					. Ansi.SetGraphic(Ansi.ATTR_OFF))
					. Ansi.SetGraphic(Ansi.FOREGROUND_RED, Ansi.ATTR_BOLD) ")"
					. Ansi.SetGraphic(Ansi.ATTR_OFF)
			}
		}
		else
		{
			if (GroupUser.options.refs)
			{
				ref := "  <-(" ref ")"
			}
		}

		return _log.Exit(text ref)
	}

	ldap_get_dn(ldapFilter)
	{
		_log := new Logger("app.gu." A_ThisFunc)
		
		if (_log.Logs(Logger.Input))
		{
			_log.Input("ldapFilter", ldapFilter)
		}

		if (!GroupUser.LDAP_CONN.Search(sr, "dc=viessmann,dc=net", ldapFilter) = Ldap.LDAP_SUCCESS)
		{
			throw _log.Exit(Exception("error: "
				. Ldap.Err2String(GroupUser.LDAP_CONN.GetLastError())))
		}

		if ((iCount := GroupUser.LDAP_CONN.CountEntries(sr)) < 0)
		{
			throw _log.Exit(Exception("error: "
				. Ldap.Err2String(GroupUser.LDAP_CONN.GetLastError())))
		}

		if (_log.Logs(Logger.Finest))
		{
			_log.Finest("iCount", iCount)
		}
		if (iCount = 0)
		{
			throw _log.Exit(Exception("error: cn not found """ ldapFilter """"
				,, GroupUser.RC_CN_NOT_FOUND))
		}
		else if (iCount > 1)
		{
			throw _log.Exit(Exception("error: cn is ambigous (" iCount ") """ ldapFilter """"
				,, GroupUser.RC_CN_AMBIGOUS))
		}
		entry := GroupUser.LDAP_CONN.FirstEntry(sr)

		return _log.Exit(GroupUser.LDAP_CONN.GetDn(entry))
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
			if (!GroupUser.options.quiet
				&& res := text.Filter(GroupUser.filter, GroupUser.options.regex
				, (GroupUser.options.ignore_case = true ? true : false)
				, GroupUser.options.invert_match))
			{
				if (_log.Logs(Logger.Finest))
				{
					_log.Finest("GroupUser.out_h", GroupUser.out_h)
				}
				if (GroupUser.out_h)
				{
					GroupUser.out_h.WriteLine((!GroupUser.options.output
						&& !GroupUser.options.append
						&& !GroupUser.options.result_only ? "   " : "") text)
				}
				else if (!GroupUser.options.count_only)
				{
					Ansi.WriteLine((!GroupUser.options.result_only ? "   ":"") text, true)
				}
			}
		}
		catch _ex
		{
			if (_log.Logs(Logger.Warning))
			{
				_log.Warning(_ex.Message)
				res := false
			}
		}
		
		return _log.Exit(res)
	}

	ldap_get_user_list(groupcn)
	{
		_log := new Logger("app.gu." A_ThisFunc)

		static n := 0
		static l := 0
		static user_list := []
		
		if (_log.Logs(Logger.Input))
		{
			_log.Input("groupcn", groupcn)
		}

		if (_log.Logs(Logger.Finest))
		{
			_log.Finest("GroupUser.group_filter", GroupUser.group_filter)
		}
		if (!GroupUser.LDAP_CONN.Search(sr, "dc=viessmann,dc=net"
			, "(&(objectclass=" GroupUser.group_filter ")(cn=" groupcn "))") = Ldap.LDAP_SUCCESS)
		{
			throw _log.Exit(Exception("error: "
				. Ldap.Err2String(GroupUser.LDAP_CONN.GetLastError())))
		}

		if ((iCount := GroupUser.LDAP_CONN.CountEntries(sr)) < 0)
		{
			throw _log.Exit(Exception("error: "
				. Ldap.Err2String(GroupUser.LDAP_CONN.GetLastError())))
		}

		if (_log.Logs(Logger.Finest))
		{
			_log.Finest("iCount", iCount)
		}
		loop %iCount%
		{
			if (A_Index = 1)
			{
				member := GroupUser.LDAP_CONN.FirstEntry(sr)
			}
			else
			{
				member := GroupUser.LDAP_CONN.NextEntry(member)
			}
			if (member)
			{
				pAttr := GroupUser.LDAP_CONN.FirstAttribute(member)
				if (_log.Logs(Logger.Finest))
				{
					_log.Finest("pAttr", pAttr)
				}
				while (pAttr)
				{
					System.StrCpy(pAttr, stAttr)
					if (_log.Logs(Logger.Finest))
					{
						_log.Finest("stAttr", stAttr)
					}
					if (stAttr = "member")
					{
						pValues := GroupUser.LDAP_CONN.GetValues(member, pAttr)
						aValues := System.PtrListToStrArray(pValues)
						if (_log.Logs(Logger.Finest))
						{
							_log.Finest("aValues:`n" LoggingHelper.Dump(aValues))
						}
						loop % aValues.MaxIndex()
						{
							if (RegExMatch(aValues[A_Index], "i)cn=(.+)\w*,\w*ou=.+\w*,.*$", $))
							{
								if (_log.Logs(Logger.Finest))
								{
									_log.Finest("$1", $1)
								}
								if (GroupUser.ldap_is_group($1))
								{
									l++
									if (l>GroupUser.options.max_nested_lv)
									{
										_log.Finest("groupcn", groupcn)
										throw _log.Exit(Exception("error: "
											. "Cyclic reference detected: `n`t" $ "`n`t<- " groupcn
											,, GroupUser.RC_CYCLE_DETECTED))
									}
									GroupUser.ldap_get_user_list($1)
									l--
								}
								else
								{
									if (user_list[$] = "")
									{
										if (GroupUser.output(GroupUser.format_output($
											, (GroupUser.options.short || !GroupUser.options.refs
											? groupcn
											: GroupUser.ldap_get_dn("cn=" groupcn)))))
										{
											n++
										}
										user_list[$] := 1
									}
								}
							}
						}
						break
					}
					pAttr := GroupUser.LDAP_CONN.NextAttribute(member)
					if (_log.Logs(Logger.Finest))
					{
						_log.Finest("pAttr", pAttr)
					}
				}
			}
		}

		if (_log.Logs(Logger.Finest))
		{
			_log.Finest("user_list:`n" LoggingHelper.Dump(user_list))
		}
		
		return _log.Exit(n)
	}

	ldap_is_group(cn)
	{
		_log := new Logger("app.gu." A_ThisFunc)
		
		if (_log.Logs(Logger.Input))
		{
			_log.Input("cn", cn)
		}

		if (!GroupUser.LDAP_CONN.Search(sr, "dc=viessmann,dc=net"
			, "(&(objectclass=" GroupUser.group_filter ")(cn=" cn "))") = Ldap.LDAP_SUCCESS)
		{
			throw _log.Exit(Exception("error: "
				. Ldap.Err2String(GroupUser.LDAP_CONN.GetLastError())))
		}

		if (GroupUser.LDAP_CONN.CountEntries(sr))
		{
			return _log.Exit(true)	
		}
		else	
		{
			return _log.Exit(false)
		}
	}

	cli() {
		_log := new Logger("class." A_ThisFunc)

		op := new OptParser("gu [-a <filename> | -o <filename>] [options] <cn> [filter]"
			,, "GU_OPTIONS")
		op.Add(new OptParser.String("a", "append", GroupUser.options, "append", "file-name"
			, "Append result to existing file"))
		op.Add(new OptParser.String("o", "", GroupUser.options, "output", "file-name"
			, "Write result to file"))
		op.Add(new OptParser.Group("`nOptions"))
		op.Add(new OptParser.Boolean("1", "short", GroupUser.options, "short"
			, "Display common names instead of the DN"))
		op.Add(new OptParser.Boolean("c", "count", GroupUser.options, "count"
			, "Display number of hits"))
		op.Add(new OptParser.Boolean("C", "count-only", GroupUser.options, "count_only"
			, "Return the number of hits as exit code; no other output"))
		op.Add(new OptParser.Boolean("e", "regex", GroupUser.options, "regex"
			, "Use a regular expression to filter the result set "
			. "(see also http://ahkscript.org/docs/misc/RegEx-QuickRef.htm)"))
		op.Add(new OptParser.String("h", "host", GroupUser.options, "host", "host-name"
			, "Hostname of the LDAP-Server (default=" GroupUser.options.host ")"
			,, GroupUser.options.host, GroupUser.options.host))
		op.Add(new OptParser.Boolean("i", "ignore-case", GroupUser.options, "ignore_case"
			, "Ignore case when filtering results", OptParser.OPT_NEG
			, GroupUser.options.ignore_case, GroupUser.options.ignore_case))
		op.Add(new OptParser.Boolean("l", "lower", GroupUser.options, "lower"
			, "Display result in lower case characters"))
		op.Add(new OptParser.Boolean("u", "upper", GroupUser.options, "upper"
			, "Display result in upper case characters"))
		op.Add(new OptParser.Boolean("r", "refs", GroupUser.options, "refs"
			, "Display relations"))
		op.Add(new OptParser.Boolean("s", "sort", GroupUser.options, "sort"
			, "Sort result"))
		op.Add(new OptParser.Boolean("v", "invert-match", GroupUser.options, "invert_match"
			, "Show not matching results"))
		op.Add(new OptParser.Boolean(0, "color", GroupUser.options, "color"
			, "Colored output (deactivated by default if -a or -o option is set)"
			, OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE, -1, true))
		op.Add(new OptParser.Boolean("R", "result-only", GroupUser.options, "result_only"
			, "Suppress any other output than the found groups"))
		op.Add(new OptParser.Boolean(0, "ibm-nested-group", GroupUser.options, "ibm_nested_group"
			, "Only chase groups which implement objectclass ibm-nestedGroup"))
		op.Add(new OptParser.String(0, "max-nested-level", GroupUser.options, "max_nested_lv", "n"
			, "Defines, which recursion depth terminates the process (default=32)"
			,, GroupUser.options.max_nested_lv, GroupUser.options.max_nested_lv))
		op.Add(new OptParser.Boolean(0, "env", GroupUser.options, "env_dummy"
			, "Ignore environment variable GU_OPTIONS"
			, OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE))
		op.Add(new OptParser.Boolean("q", "quiet", GroupUser.options, "quiet"
			, "Suppress output of results"))
		op.Add(new OptParser.Boolean(0, "version", GroupUser.options, "version"
			, "Print version info"))
		op.Add(new OptParser.Boolean(0, "help", GroupUser.options, "help"
			, "Print help", OptParser.OPT_HIDDEN))

		return _log.Exit(op)
	}

	run(args)
    {
		_log := new Logger("class." A_ThisFunc)
		
		if (_log.Logs(Logger.Input))
        {
			_log.Input("args", args)
			if (_log.Logs(Logger.Finest))
            {
				_log.Finest("args:`n" LoggingHelper.Dump(args))
			}
		}

		try
        {
			rc := GroupUser.RC_OK
			op := GroupUser.cli()
			args := op.Parse(args)
			if (_log.Logs(Logger.Finest))
            {
				_log.Finest("rc", rc)
				_log.Finest("GroupUser.options:`n" LoggingHelper.Dump(GroupUser.options))
			}

			if (GroupUser.options.help)
            {
				Ansi.WriteLine(op.Usage())
                return _log.Exit("")
            }
            else if (GroupUser.options.version)
            {
                Ansi.WriteLine(G_VERSION_INFO.NAME "/"
                    . G_VERSION_INFO.ARCH "-b" G_VERSION_INFO.BUILD)
                return _log.Exit("")
			}

            if (args.MaxIndex() < 1)
            {
                throw Exception("error: Missing argument",, GroupUser.RC_MISSING_ARG)
            }
            if (GroupUser.options.output && GroupUser.options.append)
            {
                throw Exception("error: Options '-o' and '-a' cannot be used together"
                    ,, GroupUser.RC_INVALID_ARGS)
            }
            if (GroupUser.options.upper && GroupUser.options.lower)
            {
                throw Exception("error: Options '-l' and '-u' cannot be used together"
                    ,, GroupUser.RC_INVALID_ARGS)
            }

            GroupUser.cn := args[1]
            if (args.MaxIndex() = 2)
            {
                GroupUser.filter := args[2]
            }
            if (_log.Logs(Logger.Finest))
            {
                _log.Finest("GroupUser.cn", GroupUser.cn)
                _log.Finest("GroupUser.filter", GroupUser.filter)
            }

            if (GroupUser.options.sort
                || GroupUser.options.output
                || GroupUser.options.append)
            {
				GroupUser.out_h := FileOpen(A_Temp "\__gu__.dat", "w`n")
                if ((GroupUser.options.output || GroupUser.options.append)    
                    && GroupUser.options.color <> true)
                {
                    GroupUser.options.color := false
                    if (_log.Logs(Logger.Warning))
                    {
                        _log.Warning("GroupUser.options.color has been set to false "
                            . "because of file output")
                    }
                }
            }

            if (GroupUser.options.ibm_nested_group)
            {
                GroupUser.group_filter := "ibm-nestedGroup"
            }
            if (_log.Logs(Logger.Finest))
            {
                _log.Finest("GroupUser.group_filter", GroupUser.group_filter)
            }

            if (!GroupUser.options.count_only && !GroupUser.options.result_only)
            {
                Ansi.WriteLine("Connecting to " GroupUser.options.host 
                    . ":" GroupUser.options.port "...")
            }
            GroupUser.LDAP_CONN := new Ldap(GroupUser.options.host
                , GroupUser.options.port)    
            GroupUser.LDAP_CONN.Connect()
            GroupUser.LDAP_CONN.SetOption(Ldap.OPT_VERSION, Ldap.VERSION3)
            if (!GroupUser.options.count_only && !GroupUser.options.result_only)
            {
                Ansi.WriteLine("Ok.")
                Ansi.WriteLine(GroupUser.format_output(GroupUser.ldap_get_dn("cn="
                    . GroupUser.cn), ""))
            }
            rc := GroupUser.ldap_get_user_list(GroupUser.cn)

            ; Handle sort and/or output options
            ; ---------------------------------
            if (GroupUser.out_h)
            {
                GroupUser.out_h.Close()
            }
            if (_log.Logs(Logger.Finest))
            {
                _log.Finest("GroupUser.out_h", GroupUser.out_h)
            }
            if (GroupUser.out_h)
            {
                h_gu := FileOpen(A_Temp "\__gu__.dat", "r`n")
				if (_log.Logs(Logger.Finest))
				{
					_log.Finest("h_gu", h_gu)
					_log.Finest("h_gu.Length", h_gu.Length)
				}
				content := h_gu.Read(h_gu.Length)
				h_gu.Close()
				; FileRead content, %A_Temp%\__gu__.dat
				if (GroupUser.options.sort)
				{
					Sort content
				}
				FileDelete %A_Temp%\__gu__.dat
            }

			if (GroupUser.options.append)
			{
				file_name := GroupUser.options.append
			}
			else if (GroupUser.options.output)
			{
				if (FileExist(GroupUser.options.output))
				{
					FileDelete % GroupUser.options.output
				}
				file_name := GroupUser.options.output
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

			if (GroupUser.options.count)
			{
				Ansi.WriteLine("`n" rc " Hit(s)")
			}
		}
        catch e
        {
			_log.Fatal(e.message)
			Ansi.WriteLine(e.message)
			Ansi.WriteLine(op.Usage())
			rc := e.Extra
		}
		finally
		{
			if (_log.Logs(Logger.Info))
			{
				_log.Info("Executing finally block")
			}
			if (GroupUser.LDAP_CONN)
			{
				GroupUser.LDAP_CONN.Unbind()
			}
			if (GroupUser.out_h)
			{
				GroupUser.out_h.Close()
			}
		}

		return _log.Exit(rc)
	}

}

#NoEnv										; NOTEST-BEGIN
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
#Include *i %A_ScriptDir%\gu.versioninfo
#Include <ldap>

Main:
_main := new Logger("app.groupuser.main")
exitapp _main.Exit(GroupUser.run(System.vArgs))	; NOTEST-END
; vim:tw=0:ts=4:sts=4:sw=4:noet:ft=autohotkey:bomb
